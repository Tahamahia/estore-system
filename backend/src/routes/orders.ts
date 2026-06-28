import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const orderRoutes = new Hono<AppEnv>();

/**
 * GET /orders — List orders for the current tenant
 * Supports pagination via ?page=1&limit=50
 */
orderRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;
  const status = c.req.query('status');

  let query = `SELECT * FROM orders WHERE tenant_id = ? AND is_deleted = 0`;
  const bindings: any[] = [tenantId];

  if (status) {
    query += ` AND status = ?`;
    bindings.push(status);
  }

  query += ` ORDER BY created_at DESC LIMIT ? OFFSET ?`;
  bindings.push(limit, offset);

  const results = await c.env.DB.prepare(query).bind(...bindings).all();

  const countResult = await c.env.DB.prepare(
    `SELECT COUNT(*) as total FROM orders WHERE tenant_id = ? AND is_deleted = 0`
  ).bind(tenantId).first();

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
 * GET /orders/:id — Get single order with items
 */
orderRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const orderId = c.req.param('id');

  const order = await c.env.DB.prepare(
    `SELECT * FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
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
  const allowedFields = ['status', 'notes', 'actual_exchange_rate', 'pegged_exchange_rate', 'currency'];

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

/**
 * PATCH /orders/items/bulk — Bulk update item status + tracking number
 * Used by purchasers after receiving a master tracking number for 50+ items.
 * Uses db.batch() for atomicity.
 */
orderRoutes.patch('/items/bulk', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  const { item_ids, status, shipment_id, tracking_number } = body;

  if (!item_ids?.length) {
    return c.json({ error: 'Bad Request', message: 'item_ids array is required' }, 400);
  }

  if (!status && !shipment_id) {
    return c.json({ error: 'Bad Request', message: 'Provide at least status or shipment_id' }, 400);
  }

  const stmts: D1PreparedStatement[] = [];
  const setClauses: string[] = [];

  if (status) setClauses.push(`status = '${status}'`);
  if (shipment_id) setClauses.push(`shipment_id = '${shipment_id}'`);
  setClauses.push(`updated_at = datetime('now')`);
  setClauses.push(`version = version + 1`);

  const setStr = setClauses.join(', ');

  for (const itemId of item_ids) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET ${setStr} WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(itemId, tenantId)
    );
  }

  await c.env.DB.batch(stmts);

  return c.json({
    message: `${item_ids.length} items updated`,
    updated: item_ids.length,
    status: status || undefined,
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
