import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt } from '../lib/orderStatus';

function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) chunks.push(arr.slice(i, i + size));
  return chunks;
}

export const orderRoutes = new Hono<AppEnv>();

/**
 * GET /orders — List orders for the current tenant
 * Supports pagination via ?page=1&limit=50
 * Joins customers so customer_name and customer_phone are always present.
 */
orderRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;
  const status = c.req.query('status');
  const search = c.req.query('search')?.trim();
  const unsettled = c.req.query('unsettled') === 'true';

  let query = `SELECT o.*, c.full_name as customer_name, c.phone as customer_phone,
               (SELECT COALESCE(SUM(COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1)), 0)
                FROM order_items oi WHERE oi.order_id = o.id AND oi.is_deleted = 0 AND oi.status != 'cancelled'
               ) AS items_sale_total_lyd
               FROM orders o
               LEFT JOIN customers c ON o.customer_id = c.id
               WHERE o.tenant_id = ? AND o.is_deleted = 0`;
  const bindings: any[] = [tenantId];

  if (status) {
    query += ` AND o.status = ?`;
    bindings.push(status);
  }

  if (unsettled && status === 'delivered') {
    query += ` AND o.settlement_id IS NULL`;
  }

  // Full-text search across customer name, order ID, platform order ID,
  // and item product_name / sku via an EXISTS subquery.
  if (search) {
    const like = `%${search}%`;
    query += ` AND (
      c.full_name LIKE ? OR
      o.id LIKE ? OR
      o.platform_order_id LIKE ? OR
      EXISTS (
        SELECT 1 FROM order_items oi2
        WHERE oi2.order_id = o.id
          AND oi2.tenant_id = o.tenant_id
          AND oi2.is_deleted = 0
          AND (oi2.product_name LIKE ? OR oi2.sku LIKE ?)
      )
    )`;
    bindings.push(like, like, like, like, like);
  }

  query += ` ORDER BY o.created_at DESC LIMIT ? OFFSET ?`;
  bindings.push(limit, offset);

  const results = await c.env.DB.prepare(query).bind(...bindings).all();

  let countQuery = `SELECT COUNT(*) as total FROM orders o
                    LEFT JOIN customers c ON o.customer_id = c.id
                    WHERE o.tenant_id = ? AND o.is_deleted = 0`;
  const countBindings: any[] = [tenantId];

  if (status) {
    countQuery += ` AND o.status = ?`;
    countBindings.push(status);
  }

  if (unsettled && status === 'delivered') {
    countQuery += ` AND o.settlement_id IS NULL`;
  }

  if (search) {
    const like = `%${search}%`;
    countQuery += ` AND (
      c.full_name LIKE ? OR
      o.id LIKE ? OR
      o.platform_order_id LIKE ? OR
      EXISTS (
        SELECT 1 FROM order_items oi2
        WHERE oi2.order_id = o.id
          AND oi2.tenant_id = o.tenant_id
          AND oi2.is_deleted = 0
          AND (oi2.product_name LIKE ? OR oi2.sku LIKE ?)
      )
    )`;
    countBindings.push(like, like, like, like, like);
  }

  const countResult = await c.env.DB.prepare(countQuery).bind(...countBindings).first();

  return c.json({
    data: results.results,
    pagination: {
      page,
      limit,
      total: countResult?.total || 0,
      totalPages: Math.ceil((countResult?.total as number || 0) / limit),
    },
  });
});

/**
 * POST /orders — Create a new order
 * Requires Idempotency-Key header (enforced by middleware)
 */
orderRoutes.post('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const body = await c.req.json();

  const {
    id,
    customer_id,
    platform,
    platform_order_id,
    notes,
    // New ERP fields
    cart_link,
    order_type = 'individual_items',
    total_sale_price_lyd,
    total_cost_usd,
    deposit_amount,
    deposit_note,
    items = [],
  } = body;

  if (!id || !customer_id) {
    return c.json({ error: 'Bad Request', message: 'id and customer_id are required' }, 400);
  }

  if (!cart_link?.trim()) {
    return c.json({ error: 'Bad Request', message: 'cart_link is required' }, 400);
  }

  if (order_type === 'individual_items' && !items?.length) {
    return c.json({ error: 'Bad Request', message: 'items are required for individual_items orders' }, 400);
  }

  if (deposit_amount !== undefined && deposit_amount !== null && Number(deposit_amount) < 0) {
    return c.json({ error: 'Bad Request', message: 'العربون لا يمكن أن يكون سالباً' }, 400);
  }
  if (
    order_type === 'full_cart' &&
    total_sale_price_lyd !== undefined && total_sale_price_lyd !== null &&
    deposit_amount !== undefined && deposit_amount !== null &&
    Number(deposit_amount) > Number(total_sale_price_lyd)
  ) {
    return c.json({ error: 'Bad Request', message: 'العربون لا يمكن أن يتجاوز سعر البيع الإجمالي' }, 400);
  }

  // Start a batch transaction
  const stmts: D1PreparedStatement[] = [];

  // Insert order
  stmts.push(
    c.env.DB.prepare(
      `INSERT INTO orders (id, tenant_id, customer_id, platform, platform_order_id,
       cart_link, order_type, total_sale_price_lyd, total_cost_usd,
       deposit_amount, deposit_note,
       status, notes, created_by, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(
      id, tenantId, customer_id, platform || null, platform_order_id || null,
      cart_link.trim(), order_type,
      total_sale_price_lyd ?? null, total_cost_usd ?? null,
      deposit_amount ?? 0, deposit_note?.trim() || null,
      notes || null, userId
    )
  );

  // Insert items (individual_items orders only)
  for (const item of items) {
    if (!item.id) {
      return c.json({ error: 'Bad Request', message: 'Each item must have a client-generated id' }, 400);
    }
    if (item.quantity !== undefined && item.quantity <= 0) {
      return c.json({ error: 'Bad Request', message: `الكمية يجب أن تكون أكبر من صفر (${item.product_name})` }, 400);
    }
    const numericFields = ['unit_price_foreign', 'unit_price_local', 'cost_usd', 'weight', 'shipping_rate_per_kg'];
    for (const field of numericFields) {
      if (item[field] !== undefined && item[field] !== null && Number(item[field]) < 0) {
        return c.json({ error: 'Bad Request', message: `القيمة "${field}" لا يمكن أن تكون سالبة (${item.product_name})` }, 400);
      }
    }
    stmts.push(
      c.env.DB.prepare(
        `INSERT INTO order_items (id, tenant_id, order_id, product_name, product_url,
         product_image_url, quantity, unit_price_foreign, unit_price_local,
         color, size, sku, category, attributes, cost_usd,
         notes, status, created_at, updated_at, version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'), 1)`
      ).bind(
        item.id, tenantId, id,
        item.product_name,
        item.product_url || null,
        item.product_image_url || null,
        item.quantity || 1,
        item.unit_price_foreign || 0,
        item.unit_price_local || 0,
        item.color || null, item.size || null, item.sku || null,
        item.category || null,
        item.attributes ? (typeof item.attributes === 'string' ? item.attributes : JSON.stringify(item.attributes)) : null,
        item.cost_usd ?? null,
        item.notes || null
      )
    );
  }

  try {
    await c.env.DB.batch(stmts);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return c.json({ error: 'Database Error', message: msg }, 400);
  }

  return c.json({ message: 'Order created', id }, 201);
});

// ─── FIX 2: Non-parameterized routes MUST be registered BEFORE /:id ──────

/**
 * PATCH /orders/items/bulk — Bulk update item status + tracking number
 * Used by purchasers after receiving a master tracking number for 50+ items.
 * Uses db.batch() for atomicity.
 *
 * FIX 1: Uses parameterized queries (bind()) instead of string interpolation.
 */
orderRoutes.patch('/items/bulk', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  const { item_ids, order_ids, status, external_shipment_id, tracking_number } = body;

  // D1 hard limit: 100 statements per batch() call. Use 99 to stay safely under.
  const D1_BATCH_LIMIT = 99;

  // Resolve the final list of item IDs to update
  let resolvedItemIds: string[] = item_ids || [];

  // If order_ids provided, look up all items for those orders.
  // Chunk into batches of D1_BATCH_LIMIT to avoid the 100-statement D1 limit.
  if (order_ids?.length) {
    const orderIdChunks = chunkArray(order_ids as string[], D1_BATCH_LIMIT);
    for (const chunk of orderIdChunks) {
      const stmts = chunk.map((orderId: string) =>
        c.env.DB.prepare(
          `SELECT id FROM order_items WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0`
        ).bind(orderId, tenantId)
      );
      const results = await c.env.DB.batch(stmts);
      for (const result of results) {
        const rows = result.results as any[];
        for (const row of rows) resolvedItemIds.push(row.id);
      }
    }
  }

  if (!resolvedItemIds.length) {
    return c.json({ error: 'Bad Request', message: 'item_ids or order_ids array is required' }, 400);
  }

  if (!status && !external_shipment_id) {
    return c.json({ error: 'Bad Request', message: 'Provide at least status or external_shipment_id' }, 400);
  }

  // Build parameterized SET clauses
  const setClauses: string[] = [];
  const paramValues: any[] = [];

  if (status) {
    setClauses.push(`status = ?`);
    paramValues.push(status);
  }
  if (external_shipment_id) {
    setClauses.push(`external_shipment_id = ?`);
    paramValues.push(external_shipment_id);
  }
  setClauses.push(`updated_at = datetime('now')`);
  setClauses.push(`version = version + 1`);

  const setStr = setClauses.join(', ');

  // When updating status, collect distinct order_ids so we can recompute each
  // order's derived status after all item updates are applied.
  const distinctOrderIds: string[] = [];
  if (status && resolvedItemIds.length > 0) {
    const idChunks = chunkArray(resolvedItemIds, D1_BATCH_LIMIT);
    for (const chunk of idChunks) {
      const placeholders = chunk.map(() => '?').join(', ');
      const rows = await c.env.DB.prepare(
        `SELECT DISTINCT order_id FROM order_items
         WHERE id IN (${placeholders}) AND tenant_id = ? AND order_id IS NOT NULL`
      ).bind(...chunk, tenantId).all();
      for (const row of rows.results as { order_id: string }[]) {
        if (!distinctOrderIds.includes(row.order_id)) distinctOrderIds.push(row.order_id);
      }
    }
  }

  // Build all update stmts + recompute stmts, then chunk and batch
  const allStmts: D1PreparedStatement[] = resolvedItemIds.map((itemId: string) =>
    c.env.DB.prepare(
      `UPDATE order_items SET ${setStr} WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(...paramValues, itemId, tenantId)
  );
  for (const orderId of distinctOrderIds) {
    allStmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
  }
  const allChunks = chunkArray(allStmts, D1_BATCH_LIMIT);
  for (const chunk of allChunks) {
    await c.env.DB.batch(chunk);
  }

  return c.json({
    message: `${resolvedItemIds.length} items updated`,
    updated: resolvedItemIds.length,
    status: status || undefined,
  });
});

/**
 * GET /orders/purchase-queue — All non-cancelled items still 'pending', grouped for the buying UI.
 * One row per item; the handler groups by order_id in code so the client gets a per-order list
 * with the cart link and the customer once, and its items nested underneath.
 */
orderRoutes.get('/purchase-queue', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const rows = await c.env.DB.prepare(
    `SELECT oi.id AS item_id, oi.product_name, oi.quantity, oi.sku, oi.unit_price_foreign,
            oi.cost_usd, oi.weight, oi.source_name, oi.shipping_rate_per_kg,
            oi.attributes, oi.category, oi.version,
            o.id AS order_id, o.cart_link, o.order_type, o.source_name AS order_source_name,
            o.created_at AS order_created_at,
            c.full_name AS customer_name, c.phone AS customer_phone
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id AND o.is_deleted = 0
     LEFT JOIN customers c ON c.id = o.customer_id
     WHERE oi.tenant_id = ? AND oi.is_deleted = 0 AND oi.status = 'pending'
     ORDER BY o.created_at ASC, oi.id ASC`
  ).bind(tenantId).all();

  type Row = Record<string, unknown>;
  const byOrder = new Map<string, Row>();
  let itemCount = 0;

  for (const raw of rows.results as Row[]) {
    itemCount++;
    const oid = raw.order_id as string;
    let group = byOrder.get(oid);
    if (!group) {
      group = {
        order_id: oid,
        cart_link: raw.cart_link,
        order_type: raw.order_type,
        source_name: raw.order_source_name,
        customer_name: raw.customer_name,
        customer_phone: raw.customer_phone,
        order_created_at: raw.order_created_at,
        items: [] as Row[],
      };
      byOrder.set(oid, group);
    }
    (group.items as Row[]).push({
      id: raw.item_id,
      product_name: raw.product_name,
      quantity: raw.quantity,
      sku: raw.sku,
      unit_price_foreign: raw.unit_price_foreign,
      cost_usd: raw.cost_usd,
      weight: raw.weight,
      source_name: raw.source_name,
      shipping_rate_per_kg: raw.shipping_rate_per_kg,
      attributes: raw.attributes,
      category: raw.category,
      version: raw.version,
    });
  }

  const orders = Array.from(byOrder.values());
  return c.json({
    orders,
    totals: { orders: orders.length, items: itemCount },
  });
});

/**
 * PATCH /orders/items/purchase — Bulk purchase-data save.
 * Body: { source_name?, shipping_rate_per_kg?, items: [{ id, version, sku?, cost_usd?, weight?, source_name?, shipping_rate_per_kg? }], mark_purchased: boolean }
 *
 * All items must version-match. Any mismatch → 409 and NOTHING is applied
 * (the pre-check finds all mismatches before any UPDATE runs). Chunked into
 * db.batch calls of ≤99 stmts and followed by a per-order status recompute.
 */
orderRoutes.patch('/items/purchase', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json<{
    source_name?: string;
    shipping_rate_per_kg?: number;
    items: Array<{
      id: string;
      version: number;
      sku?: string;
      cost_usd?: number;
      weight?: number;
      source_name?: string;
      shipping_rate_per_kg?: number;
    }>;
    mark_purchased: boolean;
  }>();

  if (!Array.isArray(body.items) || body.items.length === 0) {
    return c.json({ error: 'Bad Request', message: 'items array is required' }, 400);
  }

  const defaultSource = body.source_name?.trim() || null;
  const defaultRate = body.shipping_rate_per_kg;

  const D1_BATCH_LIMIT = 99;

  // Validate every item's numbers and version presence first (cheap check).
  for (const it of body.items) {
    if (!it.id || it.version === undefined || it.version === null) {
      return c.json({ error: 'Bad Request', message: 'each item needs id and version' }, 400);
    }
    if (it.cost_usd !== undefined && it.cost_usd !== null && Number(it.cost_usd) < 0) {
      return c.json({ error: 'Bad Request', message: `cost_usd لا يمكن أن يكون سالباً (${it.id})` }, 400);
    }
    if (it.weight !== undefined && it.weight !== null && Number(it.weight) < 0) {
      return c.json({ error: 'Bad Request', message: `weight لا يمكن أن يكون سالباً (${it.id})` }, 400);
    }
    if (it.shipping_rate_per_kg !== undefined && it.shipping_rate_per_kg !== null && Number(it.shipping_rate_per_kg) < 0) {
      return c.json({ error: 'Bad Request', message: `shipping_rate_per_kg لا يمكن أن يكون سالباً (${it.id})` }, 400);
    }
  }
  if (defaultRate !== undefined && defaultRate !== null && Number(defaultRate) < 0) {
    return c.json({ error: 'Bad Request', message: 'shipping_rate_per_kg لا يمكن أن يكون سالباً' }, 400);
  }

  // Version pre-check: read every item, compare, reject the whole batch on any mismatch.
  const ids = body.items.map((it) => it.id);
  const existing: Record<string, { version: number; order_id: string | null }> = {};
  for (const chunk of chunkArray(ids, D1_BATCH_LIMIT)) {
    const placeholders = chunk.map(() => '?').join(', ');
    const rows = await c.env.DB.prepare(
      `SELECT id, version, order_id FROM order_items
       WHERE id IN (${placeholders}) AND tenant_id = ? AND is_deleted = 0`
    ).bind(...chunk, tenantId).all();
    for (const row of rows.results as Array<Record<string, unknown>>) {
      existing[row.id as string] = {
        version: Number(row.version),
        order_id: (row.order_id as string | null) ?? null,
      };
    }
  }

  const mismatches: string[] = [];
  const missing: string[] = [];
  for (const it of body.items) {
    const ex = existing[it.id];
    if (!ex) { missing.push(it.id); continue; }
    if (ex.version !== Number(it.version)) mismatches.push(it.id);
  }
  if (missing.length > 0) {
    return c.json({ error: 'Not Found', message: 'بعض القطع غير موجودة', missing }, 404);
  }
  if (mismatches.length > 0) {
    return c.json({
      error: 'Conflict',
      message: 'تم تعديل بعض القطع من قبل مستخدم آخر — أعد التحميل وحاول من جديد',
      mismatches,
    }, 409);
  }

  const distinctOrderIds = new Set<string>();
  for (const it of body.items) {
    const oid = existing[it.id]?.order_id;
    if (oid) distinctOrderIds.add(oid);
  }

  const updateStmts: D1PreparedStatement[] = [];
  for (const it of body.items) {
    const setClauses: string[] = [];
    const values: unknown[] = [];

    if (it.sku !== undefined)       { setClauses.push('sku = ?');       values.push(it.sku?.trim() || null); }
    if (it.cost_usd !== undefined)  { setClauses.push('cost_usd = ?');  values.push(it.cost_usd === null ? null : Number(it.cost_usd)); }
    if (it.weight !== undefined)    { setClauses.push('weight = ?');    values.push(it.weight === null ? null : Number(it.weight)); }

    const src = it.source_name !== undefined ? (it.source_name?.trim() || null) : defaultSource;
    if (src !== null || it.source_name !== undefined) {
      setClauses.push('source_name = ?'); values.push(src);
    }

    const rate = it.shipping_rate_per_kg !== undefined
      ? (it.shipping_rate_per_kg === null ? null : Number(it.shipping_rate_per_kg))
      : (defaultRate !== undefined ? Number(defaultRate) : undefined);
    if (rate !== undefined) {
      setClauses.push('shipping_rate_per_kg = ?'); values.push(rate);
    }

    if (body.mark_purchased) {
      setClauses.push(`status = 'purchased'`);
    }

    if (setClauses.length === 0) continue; // nothing changed for this row

    setClauses.push('version = version + 1');
    setClauses.push(`updated_at = datetime('now')`);

    updateStmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET ${setClauses.join(', ')}
         WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
      ).bind(...values, it.id, tenantId, Number(it.version))
    );
  }

  const recomputeStmts = body.mark_purchased
    ? Array.from(distinctOrderIds).map((oid) => buildRecomputeOrderStatusStmt(c.env.DB, oid, tenantId))
    : [];

  const allStmts = [...updateStmts, ...recomputeStmts];
  for (const chunk of chunkArray(allStmts, D1_BATCH_LIMIT)) {
    if (chunk.length === 0) continue;
    await c.env.DB.batch(chunk);
  }

  return c.json({
    updated: updateStmts.length,
    orders_recomputed: recomputeStmts.length,
  });
});

/**
 * PATCH /orders/items/dispatch-ready — Mark sorted items as ready_dispatch for a customer
 * FIX 14: New status transition endpoint
 */
orderRoutes.patch('/items/dispatch-ready', requireRole('super_admin', 'store_manager', 'driver'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  const { customer_id } = body;

  if (!customer_id) {
    return c.json({ error: 'Bad Request', message: 'customer_id is required' }, 400);
  }

  // Find all sorted items for this customer
  const items = await c.env.DB.prepare(
    `SELECT oi.id, oi.order_id FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     WHERE o.customer_id = ? AND oi.tenant_id = ? AND oi.status = 'sorted' AND oi.is_deleted = 0`
  ).bind(customer_id, tenantId).all();

  if (!items.results?.length) {
    return c.json({ error: 'Not Found', message: 'No sorted items found for this customer' }, 404);
  }

  const affectedOrderIds = [...new Set(
    (items.results as { id: string; order_id: string }[]).map(i => i.order_id).filter(Boolean)
  )];

  const stmts: D1PreparedStatement[] = [];
  for (const item of items.results) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET status = 'ready_dispatch', updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind((item as any).id, tenantId)
    );
  }
  for (const orderId of affectedOrderIds) {
    stmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
  }

  await c.env.DB.batch(stmts);

  return c.json({
    message: `${items.results.length} items marked as ready_dispatch`,
    customer_id,
    updated: items.results.length,
  });
});

/**
 * PATCH /orders/items/dispatch — Mark ready_dispatch items as dispatched for a customer
 * FIX 14: New status transition endpoint
 */
orderRoutes.patch('/items/dispatch', requireRole('super_admin', 'store_manager', 'driver'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  const { customer_id } = body;

  if (!customer_id) {
    return c.json({ error: 'Bad Request', message: 'customer_id is required' }, 400);
  }

  // Find all ready_dispatch items for this customer
  const items = await c.env.DB.prepare(
    `SELECT oi.id, oi.order_id FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     WHERE o.customer_id = ? AND oi.tenant_id = ? AND oi.status = 'ready_dispatch' AND oi.is_deleted = 0`
  ).bind(customer_id, tenantId).all();

  if (!items.results?.length) {
    return c.json({ error: 'Not Found', message: 'No ready_dispatch items found for this customer' }, 404);
  }

  const affectedOrderIds = [...new Set(
    (items.results as { id: string; order_id: string }[]).map(i => i.order_id).filter(Boolean)
  )];

  const stmts: D1PreparedStatement[] = [];
  for (const item of items.results) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET status = 'dispatched', dispatched_at = datetime('now'), updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind((item as any).id, tenantId)
    );
  }
  for (const orderId of affectedOrderIds) {
    stmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
  }

  await c.env.DB.batch(stmts);

  return c.json({
    message: `${items.results.length} items marked as dispatched`,
    customer_id,
    updated: items.results.length,
  });
});

/**
 * GET /orders/items/unsorted — Items expected but not yet sorted
 * Used by the Visual Match feature when physical barcodes are torn/missing.
 * Returns items with thumbnails for manual identification.
 */
orderRoutes.get('/items/unsorted', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const items = await c.env.DB.prepare(
    `SELECT oi.id, oi.product_name, oi.product_image_url,
            oi.color, oi.size, oi.sku, oi.status, oi.order_id,
            c.full_name as customer_name, c.id as customer_id
     FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     LEFT JOIN customers c ON o.customer_id = c.id
     WHERE oi.tenant_id = ? AND oi.is_deleted = 0
       AND oi.status IN ('purchased', 'shipped', 'arrived_warehouse')
     ORDER BY c.full_name ASC, oi.product_name ASC`
  ).bind(tenantId).all();

  return c.json({ data: items.results, total: items.results?.length || 0 });
});

/**
 * GET /orders/items/dispatch-status — Customer dispatch readiness grouped view
 * Returns customers with their item counts and traffic-light status.
 */
orderRoutes.get('/items/dispatch-status', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(
    `SELECT 
       c.id as customer_id,
       c.full_name as customer_name,
       c.phone,
       COUNT(oi.id) as total_items,
       SUM(CASE WHEN oi.status = 'sorted' OR oi.status = 'ready_dispatch' THEN 1 ELSE 0 END) as ready_items,
       SUM(CASE WHEN oi.status IN ('purchased','shipped','arrived_warehouse') THEN 1 ELSE 0 END) as pending_items,
       SUM(CASE WHEN oi.status = 'pending' THEN 1 ELSE 0 END) as not_ordered_items
     FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     LEFT JOIN customers c ON o.customer_id = c.id
     WHERE oi.tenant_id = ? AND oi.is_deleted = 0
       AND oi.status NOT IN ('delivered', 'cancelled', 'refunded', 'dispatched')
     GROUP BY c.id
     ORDER BY ready_items DESC, c.full_name ASC`
  ).bind(tenantId).all();

  return c.json({ data: results.results });
});

// ─── Parameterized routes (must be AFTER non-parameterized routes) ──────

/**
 * PATCH /orders/items/:item_id/weight — Set actual_weight and volumetric_weight on an order item
 * Needed for Landed Cost calculation with real data.
 * Uses OCC with version column.
 */
orderRoutes.patch('/items/:item_id/weight', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const itemId = c.req.param('item_id');
  const body = await c.req.json();
  const { actual_weight, volumetric_weight, version } = body;

  if (!version) {
    return c.json({ error: 'Bad Request', message: 'version field required for OCC' }, 400);
  }

  if (actual_weight === undefined && volumetric_weight === undefined) {
    return c.json({ error: 'Bad Request', message: 'Provide actual_weight and/or volumetric_weight' }, 400);
  }

  const setClauses: string[] = [];
  const values: any[] = [];

  if (actual_weight !== undefined) {
    setClauses.push(`actual_weight = ?`);
    values.push(actual_weight);
  }
  if (volumetric_weight !== undefined) {
    setClauses.push(`volumetric_weight = ?`);
    values.push(volumetric_weight);
  }

  setClauses.push(`version = version + 1`);
  setClauses.push(`updated_at = datetime('now')`);

  const result = await c.env.DB.prepare(
    `UPDATE order_items SET ${setClauses.join(', ')}
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, itemId, tenantId, version).run();

  if (result.meta.changes === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Item was modified by another request (version mismatch) or not found'
    }, 409);
  }

  return c.json({ message: 'Weight updated', id: itemId });
});

/**
 * POST /orders/:id/items — Add a single item to an existing order
 */
orderRoutes.post('/:id/items', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');
  const body = await c.req.json();

  const { id, product_name, product_url, product_image_url, quantity, unit_price_foreign, unit_price_local, color, size, sku, notes, category, weight, brand, source_name, shipping_rate_per_kg } = body;

  if (!id || !product_name) {
    return c.json({ error: 'Bad Request', message: 'id and product_name are required' }, 400);
  }

  const order = await c.env.DB.prepare(
    `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first();

  if (!order) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  if (quantity !== undefined && quantity <= 0) {
    return c.json({ error: 'Bad Request', message: 'الكمية يجب أن تكون أكبر من صفر' }, 400);
  }
  const numericItemFields = ['unit_price_foreign', 'unit_price_local', 'cost_usd', 'weight', 'shipping_rate_per_kg'];
  for (const field of numericItemFields) {
    if (body[field] !== undefined && body[field] !== null && Number(body[field]) < 0) {
      return c.json({ error: 'Bad Request', message: `القيمة "${field}" لا يمكن أن تكون سالبة` }, 400);
    }
  }

  await c.env.DB.prepare(
    `INSERT INTO order_items (id, tenant_id, order_id, product_name, product_url,
     product_image_url, quantity, unit_price_foreign, unit_price_local,
     color, size, sku, category, weight, brand, notes, source_name, shipping_rate_per_kg,
     status, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'), 1)`
  ).bind(
    id, tenantId, orderId, product_name, product_url || null,
    product_image_url || null, quantity || 1,
    unit_price_foreign || 0, unit_price_local || 0,
    color || null, size || null, sku || null,
    category || null, weight || 0, brand || null, notes || null,
    source_name || null, shipping_rate_per_kg || 0
  ).run();

  return c.json({ message: 'Item added', id }, 201);
});

/**
 * PATCH /orders/:id/items/:itemId — Update a single order item (all fields + status)
 * Uses OCC via the version column to prevent lost-update races.
 */
orderRoutes.patch('/:id/items/:itemId', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');
  const itemId = c.req.param('itemId');
  const body = await c.req.json();
  const { version, ...updates } = body;

  if (version === undefined || version === null) {
    return c.json({ error: 'Bad Request', message: 'version required for OCC' }, 400);
  }

  if (updates.quantity !== undefined && updates.quantity <= 0) {
    return c.json({ error: 'Bad Request', message: 'الكمية يجب أن تكون أكبر من صفر' }, 400);
  }
  const numericPatchFields = ['unit_price_foreign', 'unit_price_local', 'cost_usd', 'weight', 'shipping_rate_per_kg'];
  for (const field of numericPatchFields) {
    if (updates[field] !== undefined && updates[field] !== null && Number(updates[field]) < 0) {
      return c.json({ error: 'Bad Request', message: `القيمة "${field}" لا يمكن أن تكون سالبة` }, 400);
    }
  }

  const allowedFields = ['product_name', 'product_url', 'unit_price_foreign', 'unit_price_local', 'quantity', 'size', 'color', 'sku', 'status', 'weight', 'brand', 'source_name', 'shipping_rate_per_kg', 'category', 'attributes', 'cost_usd'];
  const floatFields = new Set(['unit_price_foreign', 'unit_price_local', 'weight', 'shipping_rate_per_kg', 'cost_usd']);
  const setClauses: string[] = [];
  const values: any[] = [];

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      setClauses.push(`${field} = ?`);
      const raw = updates[field] === '' ? null : updates[field];
      values.push(raw !== null && floatFields.has(field) ? parseFloat(String(raw)) || 0 : raw);
    }
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'Bad Request', message: 'No valid fields to update' }, 400);
  }

  setClauses.push(`version = version + 1`);
  setClauses.push(`updated_at = datetime('now')`);

  const itemStmt = c.env.DB.prepare(
    `UPDATE order_items SET ${setClauses.join(', ')}
     WHERE id = ? AND order_id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, itemId, orderId, tenantId, version);

  const batchStmts: D1PreparedStatement[] = [itemStmt];
  if (updates.status !== undefined) {
    batchStmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
  }

  let batchResults;
  try {
    batchResults = await c.env.DB.batch(batchStmts);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return c.json({ error: 'Database Error', message: msg }, 400);
  }

  if ((batchResults[0].meta.changes ?? 0) === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Item was modified by another request (version mismatch) or not found',
    }, 409);
  }

  return c.json({ message: 'Item updated', id: itemId });
});

/**
 * POST /orders/:id/split — Split an order by moving selected items into a new linked child order.
 * Useful for partial fulfilment: some items are ready, others are still pending.
 * Payload: { item_ids: string[], moved_sale_price_lyd?: number, moved_cost_usd?: number }
 */
orderRoutes.post('/:id/split', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const orderId = c.req.param('id') as string;
  const body = await c.req.json();
  const { item_ids, moved_sale_price_lyd, moved_cost_usd } = body as {
    item_ids?: string[];
    moved_sale_price_lyd?: number;
    moved_cost_usd?: number;
  };

  if (!item_ids?.length) {
    return c.json({ error: 'Bad Request', message: 'item_ids is required and must be non-empty' }, 400);
  }

  // Fetch the parent order
  const parentOrder = await c.env.DB.prepare(
    `SELECT id, tenant_id, customer_id, platform, cart_link, order_type,
            total_sale_price_lyd, total_cost_usd, notes, version
     FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first() as Record<string, unknown> | null;

  if (!parentOrder) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  // Verify all item_ids belong to this order and are not soft-deleted
  const placeholders = item_ids.map(() => '?').join(', ');
  const movedItemRows = await c.env.DB.prepare(
    `SELECT id, status FROM order_items
     WHERE id IN (${placeholders}) AND order_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(...item_ids, orderId, tenantId).all();

  if ((movedItemRows.results?.length ?? 0) !== item_ids.length) {
    return c.json({
      error: 'Bad Request',
      message: 'بعض العناصر المحددة غير موجودة أو لا تنتمي لهذه الطلبية',
    }, 400);
  }

  // Must leave at least 1 item in the original order
  const totalItemCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as total FROM order_items WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first() as { total: number } | null;

  if ((totalItemCount?.total ?? 0) <= item_ids.length) {
    return c.json({
      error: 'Bad Request',
      message: 'يجب أن يبقى منتج واحد على الأقل في الطلبية الأصلية',
    }, 400);
  }

  // full_cart orders require an explicit moved sale price
  if (parentOrder.order_type === 'full_cart') {
    if (moved_sale_price_lyd === undefined || moved_sale_price_lyd === null || isNaN(Number(moved_sale_price_lyd))) {
      return c.json({
        error: 'Bad Request',
        message: 'يجب تحديد قيمة القطع المنقولة يدوياً لأن الطلبية سلة تامة',
      }, 400);
    }
  }

  // Derive the new order's status from the EARLIEST (furthest-behind) moved item
  const statusPriority: Record<string, number> = {
    pending: 0, purchased: 1, shipped: 2, arrived_warehouse: 3,
    sorted: 4, ready_dispatch: 5, dispatched: 6, delivered: 7,
    cancelled: 8, refunded: 8, transferred_to_inventory: 8, in_stock: 8,
  };
  let derivedStatus = 'pending';
  let lowestPriority = 999;
  for (const row of movedItemRows.results as { id: string; status: string }[]) {
    const p = statusPriority[row.status] ?? 0;
    if (p < lowestPriority) {
      lowestPriority = p;
      derivedStatus = row.status;
    }
  }

  const newOrderId = crypto.randomUUID();
  const isFullCart = parentOrder.order_type === 'full_cart';

  const stmts: D1PreparedStatement[] = [];

  // 1. Insert new child order
  stmts.push(
    c.env.DB.prepare(
      `INSERT INTO orders (id, tenant_id, customer_id, platform, cart_link, order_type,
       parent_order_id, status,
       total_sale_price_lyd, total_cost_usd,
       notes, created_by, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(
      newOrderId,
      tenantId,
      parentOrder.customer_id,
      parentOrder.platform || null,
      parentOrder.cart_link || null,
      parentOrder.order_type,
      orderId,
      derivedStatus,
      isFullCart ? (moved_sale_price_lyd ?? null) : null,
      isFullCart ? (moved_cost_usd ?? null) : null,
      parentOrder.notes || null,
      userId,
    )
  );

  // 2. Reassign the moved items to the new order
  for (const itemId of item_ids) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET order_id = ?, updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ?`
      ).bind(newOrderId, itemId, tenantId)
    );
  }

  // 3. Update the original order: subtract totals (full_cart), then recompute status from remaining items
  if (isFullCart) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE orders
         SET total_sale_price_lyd = COALESCE(total_sale_price_lyd, 0) - ?,
             total_cost_usd       = COALESCE(total_cost_usd, 0) - ?,
             version              = version + 1,
             updated_at           = datetime('now')
         WHERE id = ? AND tenant_id = ?`
      ).bind(moved_sale_price_lyd ?? 0, moved_cost_usd ?? 0, orderId, tenantId)
    );
  }
  // Recompute the original order's status from its remaining items (replaces the plain
  // version-bump that was here for individual_items, and also runs for full_cart).
  stmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));

  try {
    await c.env.DB.batch(stmts);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return c.json({ error: 'Database Error', message: msg }, 400);
  }

  return c.json({ new_order_id: newOrderId, message: 'تم إنشاء الطلبية الجديدة' }, 201);
});

/**
 * GET /orders/:id — Get single order with items and customer info
 */
orderRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');

  const order = await c.env.DB.prepare(
    `SELECT o.*, c.full_name as customer_name, c.phone as customer_phone,
            c.phone2 as customer_phone2, c.city as customer_city,
            c.area as customer_area, c.street as customer_street,
            c.location_url as customer_location_url
     FROM orders o
     LEFT JOIN customers c ON o.customer_id = c.id
     WHERE o.id = ? AND o.tenant_id = ? AND o.is_deleted = 0`
  ).bind(orderId, tenantId).first();

  if (!order) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  const items = await c.env.DB.prepare(
    `SELECT * FROM order_items WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).all();

  const childOrders = await c.env.DB.prepare(
    `SELECT id, status, created_at FROM orders WHERE parent_order_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).all();

  return c.json({ ...order, items: items.results, child_orders: childOrders.results });
});

/**
 * PATCH /orders/:id — Update order (with Optimistic Concurrency Control)
 */
orderRoutes.patch('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');
  const body = await c.req.json();
  const { version, ...updates } = body;

  if (version === undefined || version === null) {
    return c.json({ error: 'Bad Request', message: 'version field required for OCC' }, 400);
  }

  if (updates.deposit_amount !== undefined && updates.deposit_amount !== null && Number(updates.deposit_amount) < 0) {
    return c.json({ error: 'Bad Request', message: 'العربون لا يمكن أن يكون سالباً' }, 400);
  }

  // Build dynamic SET clause
  const setClauses: string[] = [];
  const values: any[] = [];
  const allowedFields = ['notes', 'shipping_rate_per_kg', 'cart_link', 'order_type', 'total_sale_price_lyd', 'total_cost_usd', 'deposit_amount', 'deposit_note', 'source_name'];

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      setClauses.push(`${field} = ?`);
      values.push(updates[field]);
    }
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'Bad Request', message: 'No valid fields to update' }, 400);
  }

  setClauses.push(`version = version + 1`);
  setClauses.push(`updated_at = datetime('now')`);

  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `UPDATE orders SET ${setClauses.join(', ')}
       WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
    ).bind(...values, orderId, tenantId, version),
  ];

  let results;
  try {
    results = await c.env.DB.batch(stmts);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return c.json({ error: 'Database Error', message: msg }, 400);
  }

  if ((results[0].meta.changes ?? 0) === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Order was modified by another request (version mismatch) or not found'
    }, 409);
  }

  return c.json({ message: 'Order updated', id: orderId });
});

/**
 * DELETE /orders/:id — Soft delete an order
 */
orderRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const orderId = c.req.param('id');

  const result = await c.env.DB.prepare(
    `UPDATE orders SET is_deleted = 1, deleted_by = ?, deleted_at = datetime('now'), updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(userId, orderId, tenantId).run();

  if (result.meta.changes === 0) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  return c.json({ message: 'Order soft-deleted', id: orderId });
});

/**
 * POST /orders/:id/orphan-items — Cancel order and move all purchased items to in-stock inventory.
 * Live cost fields (unit_price_foreign, cost_usd, weight, shipping_rate_per_kg) are preserved as sunk costs for settlement.
 */
orderRoutes.post('/:id/orphan-items', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');

  const order = await c.env.DB.prepare(
    `SELECT id, status FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first();
  if (!order) return c.json({ error: 'Order not found' }, 404);

  const terminalStatuses = ['cancelled', 'refunded', 'delivered', 'transferred_to_inventory', 'in_stock'];
  if (terminalStatuses.includes((order as Record<string, unknown>).status as string)) {
    return c.json({ error: `Cannot orphan items from a ${(order as Record<string, unknown>).status as string} order` }, 400);
  }

  await c.env.DB.batch([
    // Cancel the parent order
    c.env.DB.prepare(
      `UPDATE orders SET status = 'cancelled', updated_at = datetime('now'), version = version + 1
       WHERE id = ? AND tenant_id = ?`
    ).bind(orderId, tenantId),
    // Detach items and move to in-stock; costs are intentionally preserved as sunk costs
    c.env.DB.prepare(`
      UPDATE order_items
      SET order_id  = NULL,
          status    = 'in_stock',
          updated_at = datetime('now'),
          version   = version + 1
      WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0
        AND status NOT IN ('cancelled', 'refunded', 'delivered')
    `).bind(orderId, tenantId),
  ]);

  return c.json({ message: 'Order cancelled and items moved to in-stock', order_id: orderId });
});
