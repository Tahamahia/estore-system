import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt } from '../lib/orderStatus';

export const inventoryRoutes = new Hono<AppEnv>();

inventoryRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;
  const results = await c.env.DB.prepare(
    `SELECT * FROM local_inventory WHERE tenant_id = ? AND is_deleted = 0 ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).bind(tenantId, limit, offset).all();
  return c.json({ data: results.results, page, limit });
});

inventoryRoutes.post('/transfer', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const { id, order_item_id, reason } = await c.req.json();
  if (!id || !order_item_id) return c.json({ error: 'id and order_item_id required' }, 400);

  const item = await c.env.DB.prepare(
    `SELECT * FROM order_items WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(order_item_id, tenantId).first();
  if (!item) return c.json({ error: 'Item not found' }, 404);

  const stmts = [
    c.env.DB.prepare(
      `INSERT INTO local_inventory (id, tenant_id, original_item_id, product_name, purchase_price, status, reason, transferred_by, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, 'available', ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(id, tenantId, order_item_id, (item as any).product_name, (item as any).unit_price_local, reason || 'cancelled', userId),
    c.env.DB.prepare(
      `UPDATE order_items SET status = 'transferred_to_inventory', updated_at = datetime('now') WHERE id = ? AND tenant_id = ?`
    ).bind(order_item_id, tenantId)
  ];
  await c.env.DB.batch(stmts);
  return c.json({ message: 'Item transferred to local inventory', id }, 201);
});

// GET /inventory/in-stock — orphaned items available for reassignment
inventoryRoutes.get('/in-stock', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(`
    SELECT id, product_name, product_url, product_image_url, product_thumb_url,
           sku, brand, item_category, color, size, quantity,
           purchase_price, shipping_cost_foreign, landed_cost,
           unit_price_local, status, updated_at
    FROM order_items
    WHERE tenant_id = ? AND order_id IS NULL AND status = 'in_stock' AND is_deleted = 0
    ORDER BY updated_at DESC
  `).bind(tenantId).all();

  return c.json({ data: results.results });
});

// PATCH /inventory/in-stock/:item_id/reassign — zero costs and attach to new order
inventoryRoutes.patch('/in-stock/:item_id/reassign', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const itemId = c.req.param('item_id');
  const { order_id, new_selling_price } = await c.req.json<{ order_id: string; new_selling_price: number }>();

  if (!order_id) return c.json({ error: 'order_id required' }, 400);
  if (typeof new_selling_price !== 'number' || new_selling_price < 0) {
    return c.json({ error: 'new_selling_price must be a non-negative number' }, 400);
  }

  const item = await c.env.DB.prepare(
    `SELECT id FROM order_items WHERE id = ? AND tenant_id = ? AND status = 'in_stock' AND order_id IS NULL AND is_deleted = 0`
  ).bind(itemId, tenantId).first();
  if (!item) return c.json({ error: 'Item not found or not available in-stock' }, 404);

  const order = await c.env.DB.prepare(
    `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(order_id, tenantId).first();
  if (!order) return c.json({ error: 'Target order not found' }, 404);

  // Zero out all costs — the entire selling price becomes pure net profit
  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE order_items
      SET order_id           = ?,
          status             = 'sorted',
          unit_price_local   = ?,
          purchase_price     = 0,
          shipping_cost_foreign = 0,
          landed_cost        = 0,
          net_profit         = ?,
          updated_at         = datetime('now'),
          version            = version + 1
      WHERE id = ? AND tenant_id = ?
    `).bind(order_id, new_selling_price, new_selling_price, itemId, tenantId),
    buildRecomputeOrderStatusStmt(c.env.DB, order_id, tenantId),
  ]);

  return c.json({ message: 'Item reassigned as pure-profit', item_id: itemId, order_id, net_profit: new_selling_price });
});
