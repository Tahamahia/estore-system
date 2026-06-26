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
         product_image_url, quantity, unit_price_foreign, unit_price_local, color, size, 
         notes, status, created_at, updated_at, version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'), 1)`
      ).bind(
        item.id, tenantId, id, item.product_name, item.product_url || null,
        item.product_image_url || null, item.quantity || 1,
        item.unit_price_foreign || 0, item.unit_price_local || 0,
        item.color || null, item.size || null, item.notes || null
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
