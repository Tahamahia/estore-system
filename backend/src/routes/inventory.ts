import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

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
