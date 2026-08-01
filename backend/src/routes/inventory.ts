import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt } from '../lib/orderStatus';

export const inventoryRoutes = new Hono<AppEnv>();

// GET /inventory/in-stock — orphaned items available for reassignment, with search + pagination
inventoryRoutes.get('/in-stock', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = Math.max(1, parseInt(c.req.query('page') || '1'));
  const limit = Math.min(parseInt(c.req.query('limit') || '20'), 100);
  const offset = (page - 1) * limit;
  const search = (c.req.query('search') ?? '').trim();

  // Build dynamic WHERE bindings
  const baseWhere = `tenant_id = ? AND order_id IS NULL AND status = 'in_stock' AND is_deleted = 0`;
  const baseBindings: unknown[] = [tenantId];
  const searchWhere = search ? ` AND (product_name LIKE ? OR sku LIKE ?)` : '';
  const searchBindings: unknown[] = search ? [`%${search}%`, `%${search}%`] : [];

  const allBindings = [...baseBindings, ...searchBindings];
  const fullWhere = baseWhere + searchWhere;

  const totalResult = await c.env.DB.prepare(
    `SELECT COUNT(*) AS total FROM order_items WHERE ${fullWhere}`
  ).bind(...allBindings).first<{ total: number }>();

  const results = await c.env.DB.prepare(`
    SELECT id, product_name, product_url, product_image_url, product_thumb_url,
           sku, brand, item_category, color, size, quantity,
           unit_price_foreign, cost_usd, weight, shipping_rate_per_kg,
           unit_price_local, status, updated_at, written_off_settlement_id
    FROM order_items
    WHERE ${fullWhere}
    ORDER BY updated_at DESC
    LIMIT ? OFFSET ?
  `).bind(...allBindings, limit, offset).all();

  return c.json({ data: results.results, total: totalResult?.total ?? 0, page, limit });
});

// PATCH /inventory/in-stock/:item_id/reassign — zero costs and attach to new or existing order
inventoryRoutes.patch('/in-stock/:item_id/reassign', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const itemId = c.req.param('item_id');
  const { order_id, new_selling_price, new_customer_phone, new_customer_name } = await c.req.json<{
    order_id?: string;
    new_selling_price: number;
    new_customer_phone?: string;
    new_customer_name?: string;
  }>();

  if (!order_id && !new_customer_phone) {
    return c.json({ error: 'order_id or new_customer_phone required' }, 400);
  }
  if (typeof new_selling_price !== 'number' || new_selling_price < 0) {
    return c.json({ error: 'new_selling_price must be a non-negative number' }, 400);
  }

  const item = await c.env.DB.prepare(
    `SELECT id FROM order_items WHERE id = ? AND tenant_id = ? AND status = 'in_stock' AND order_id IS NULL AND is_deleted = 0`
  ).bind(itemId, tenantId).first();
  if (!item) return c.json({ error: 'Item not found or not available in-stock' }, 404);

  let targetOrderId = order_id;

  if (!targetOrderId && new_customer_phone) {
    // Lookup or create customer by phone
    const existing = await c.env.DB.prepare(
      `SELECT id FROM customers WHERE phone = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(new_customer_phone.trim(), tenantId).first<{ id: string }>();

    let customerId: string;
    if (existing) {
      customerId = existing.id;
    } else {
      customerId = crypto.randomUUID();
      await c.env.DB.prepare(
        `INSERT INTO customers (id, tenant_id, full_name, phone, created_at, updated_at, version)
         VALUES (?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
      ).bind(customerId, tenantId, (new_customer_name || new_customer_phone).trim(), new_customer_phone.trim()).run();
    }

    // Create a bare-bones order for this customer (status sorted = item already in hand)
    targetOrderId = crypto.randomUUID();
    await c.env.DB.prepare(
      `INSERT INTO orders (id, tenant_id, customer_id, status, created_at, updated_at, version)
       VALUES (?, ?, ?, 'sorted', datetime('now'), datetime('now'), 1)`
    ).bind(targetOrderId, tenantId, customerId).run();
  }

  // Verify target order belongs to this tenant
  const order = await c.env.DB.prepare(
    `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(targetOrderId, tenantId).first();
  if (!order) return c.json({ error: 'Target order not found' }, 404);

  // Zero out all costs — the entire selling price becomes pure net profit
  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE order_items
      SET order_id              = ?,
          status                = 'sorted',
          unit_price_local      = ?,
          unit_price_foreign    = 0,
          cost_usd              = 0,
          weight                = 0,
          shipping_rate_per_kg  = 0,
          updated_at            = datetime('now'),
          version               = version + 1
      WHERE id = ? AND tenant_id = ?
    `).bind(targetOrderId, new_selling_price, itemId, tenantId),
    buildRecomputeOrderStatusStmt(c.env.DB, targetOrderId as string, tenantId),
  ]);

  return c.json({ message: 'Item reassigned as pure-profit', item_id: itemId, order_id: targetOrderId, net_profit: new_selling_price });
});
