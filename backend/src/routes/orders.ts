import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

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

  let query = `SELECT o.*, c.full_name as customer_name, c.phone as customer_phone
               FROM orders o
               LEFT JOIN customers c ON o.customer_id = c.id
               WHERE o.tenant_id = ? AND o.is_deleted = 0`;
  const bindings: any[] = [tenantId];

  if (status) {
    query += ` AND o.status = ?`;
    bindings.push(status);
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
    id,            // Client-generated UUID v4
    customer_id,
    platform,
    platform_order_id,
    pegged_exchange_rate,
    currency,
    notes,
    items,         // Array of order items
  } = body;

  if (!id || !customer_id || !items?.length) {
    return c.json({ error: 'Bad Request', message: 'id, customer_id, and items are required' }, 400);
  }

  // Start a batch transaction
  const stmts: D1PreparedStatement[] = [];

  // Insert order
  stmts.push(
    c.env.DB.prepare(
      `INSERT INTO orders (id, tenant_id, customer_id, platform, platform_order_id, 
       pegged_exchange_rate, currency, status, notes, created_by, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending_payment', ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(id, tenantId, customer_id, platform || null, platform_order_id || null,
           pegged_exchange_rate || null, currency || 'USD', notes || null, userId)
  );

  // Insert each item with unique Item_UID
  for (const item of items) {
    if (!item.id) {
      return c.json({ error: 'Bad Request', message: 'Each item must have a client-generated id' }, 400);
    }
    stmts.push(
      c.env.DB.prepare(
        `INSERT INTO order_items (id, tenant_id, order_id, product_name, product_url, 
         product_image_url, quantity, unit_price_foreign, unit_price_local, color, size, sku,
         notes, status, created_at, updated_at, version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'), 1)`
      ).bind(
        item.id, tenantId, id, item.product_name, item.product_url || null,
        item.product_image_url || null, item.quantity || 1,
        item.unit_price_foreign || 0, item.unit_price_local || 0,
        item.color || null, item.size || null, item.sku || null, item.notes || null
      )
    );
  }

  await c.env.DB.batch(stmts);

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
  const { item_ids, order_ids, status, shipment_id, tracking_number } = body;

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

  if (!status && !shipment_id) {
    return c.json({ error: 'Bad Request', message: 'Provide at least status or shipment_id' }, 400);
  }

  // Build parameterized SET clauses
  const setClauses: string[] = [];
  const paramValues: any[] = [];

  if (status) {
    setClauses.push(`status = ?`);
    paramValues.push(status);
  }
  if (shipment_id) {
    setClauses.push(`shipment_id = ?`);
    paramValues.push(shipment_id);
  }
  setClauses.push(`updated_at = datetime('now')`);
  setClauses.push(`version = version + 1`);

  const setStr = setClauses.join(', ');

  // Chunk updates to stay under the D1 batch limit
  const updateChunks = chunkArray(resolvedItemIds, D1_BATCH_LIMIT);
  for (const chunk of updateChunks) {
    const updateStmts = chunk.map((itemId: string) =>
      c.env.DB.prepare(
        `UPDATE order_items SET ${setStr} WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(...paramValues, itemId, tenantId)
    );
    await c.env.DB.batch(updateStmts);
  }

  return c.json({
    message: `${resolvedItemIds.length} items updated`,
    updated: resolvedItemIds.length,
    status: status || undefined,
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
    `SELECT oi.id FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     WHERE o.customer_id = ? AND oi.tenant_id = ? AND oi.status = 'sorted' AND oi.is_deleted = 0`
  ).bind(customer_id, tenantId).all();

  if (!items.results?.length) {
    return c.json({ error: 'Not Found', message: 'No sorted items found for this customer' }, 404);
  }

  const stmts: D1PreparedStatement[] = [];
  for (const item of items.results) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET status = 'ready_dispatch', updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(item.id, tenantId)
    );
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
    `SELECT oi.id FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     WHERE o.customer_id = ? AND oi.tenant_id = ? AND oi.status = 'ready_dispatch' AND oi.is_deleted = 0`
  ).bind(customer_id, tenantId).all();

  if (!items.results?.length) {
    return c.json({ error: 'Not Found', message: 'No ready_dispatch items found for this customer' }, 404);
  }

  const stmts: D1PreparedStatement[] = [];
  for (const item of items.results) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET status = 'dispatched', dispatched_at = datetime('now'), updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(item.id, tenantId)
    );
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
    `SELECT oi.id, oi.product_name, oi.product_image_url, oi.product_thumb_url,
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

  const { id, product_name, product_url, product_image_url, quantity, unit_price_foreign, unit_price_local, shipping_cost_foreign, color, size, sku, notes, item_category, weight, brand, source_name, shipping_rate_per_kg } = body;

  if (!id || !product_name) {
    return c.json({ error: 'Bad Request', message: 'id and product_name are required' }, 400);
  }

  const order = await c.env.DB.prepare(
    `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first();

  if (!order) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  await c.env.DB.prepare(
    `INSERT INTO order_items (id, tenant_id, order_id, product_name, product_url,
     product_image_url, quantity, unit_price_foreign, unit_price_local, shipping_cost_foreign,
     color, size, sku, item_category, weight, brand, notes, source_name, shipping_rate_per_kg,
     status, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'), 1)`
  ).bind(
    id, tenantId, orderId, product_name, product_url || null,
    product_image_url || null, quantity || 1,
    unit_price_foreign || 0, unit_price_local || 0, shipping_cost_foreign || 0,
    color || null, size || null, sku || null,
    item_category || null, weight || 0, brand || null, notes || null,
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

  if (!version) {
    return c.json({ error: 'Bad Request', message: 'version required for OCC' }, 400);
  }

  const allowedFields = ['product_name', 'product_url', 'unit_price_foreign', 'unit_price_local', 'shipping_cost_foreign', 'quantity', 'size', 'color', 'sku', 'status', 'item_category', 'weight', 'brand', 'source_name', 'shipping_rate_per_kg'];
  const setClauses: string[] = [];
  const values: any[] = [];

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      setClauses.push(`${field} = ?`);
      values.push(updates[field] === '' ? null : updates[field]);
    }
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'Bad Request', message: 'No valid fields to update' }, 400);
  }

  setClauses.push(`version = version + 1`);
  setClauses.push(`updated_at = datetime('now')`);

  const result = await c.env.DB.prepare(
    `UPDATE order_items SET ${setClauses.join(', ')}
     WHERE id = ? AND order_id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, itemId, orderId, tenantId, version).run();

  if (result.meta.changes === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Item was modified by another request (version mismatch) or not found',
    }, 409);
  }

  return c.json({ message: 'Item updated', id: itemId });
});

/**
 * GET /orders/:id — Get single order with items and customer info
 */
orderRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');

  const order = await c.env.DB.prepare(
    `SELECT o.*, c.full_name as customer_name, c.phone as customer_phone
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

  return c.json({ ...order, items: items.results });
});

/**
 * PATCH /orders/:id — Update order (with Optimistic Concurrency Control)
 */
orderRoutes.patch('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');
  const body = await c.req.json();
  const { version, ...updates } = body;

  if (!version) {
    return c.json({ error: 'Bad Request', message: 'version field required for OCC' }, 400);
  }

  // Build dynamic SET clause
  const setClauses: string[] = [];
  const values: any[] = [];
  const allowedFields = ['status', 'notes', 'actual_exchange_rate', 'pegged_exchange_rate', 'currency', 'total_local', 'shipping_cost_foreign', 'shipping_rate_per_kg'];

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

  const result = await c.env.DB.prepare(
    `UPDATE orders SET ${setClauses.join(', ')} 
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, orderId, tenantId, version).run();

  if (result.meta.changes === 0) {
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
