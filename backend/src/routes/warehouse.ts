import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const warehouseRoutes = new Hono<AppEnv>();

warehouseRoutes.post('/scan', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const { barcode } = await c.req.json<{ barcode: string }>();
  if (!barcode) return c.json({ error: 'barcode required' }, 400);

  // Lookup chain: item_uid → sku → tracking_number
  let items = await c.env.DB.prepare(
    `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
     JOIN orders o ON oi.order_id = o.id LEFT JOIN customers c ON o.customer_id = c.id
     WHERE oi.item_uid = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
  ).bind(barcode, tenantId).all();

  // Fallback 2: Search by SKU (Shein/Trendyol physical barcode)
  if (!items.results?.length) {
    items = await c.env.DB.prepare(
      `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
       JOIN orders o ON oi.order_id = o.id LEFT JOIN customers c ON o.customer_id = c.id
       WHERE oi.sku = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(barcode, tenantId).all();
  }

  // Fallback 3: Search by tracking number
  if (!items.results?.length) {
    items = await c.env.DB.prepare(
      `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
       JOIN orders o ON oi.order_id = o.id JOIN shipments s ON oi.shipment_id = s.id
       LEFT JOIN customers c ON o.customer_id = c.id
       WHERE s.tracking_number = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(barcode, tenantId).all();
  }

  if (!items.results?.length) return c.json({ found: false, barcode });

  if (items.results.length > 1) {
    return c.json({ found: true, ambiguous: true, candidates: items.results.map((i: any) => ({
      item_id: i.id, product_name: i.product_name, customer_name: i.customer_name, status: i.status,
    }))});
  }

  const item = items.results[0] as any;
  await c.env.DB.prepare(
    `UPDATE order_items SET status = 'sorted', sorted_at = datetime('now'), updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(item.id, tenantId).run();

  return c.json({ found: true, ambiguous: false, item: { id: item.id, product_name: item.product_name, customer_name: item.customer_name, status: 'sorted' }});
});

warehouseRoutes.post('/orphan', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const { id, barcode, description, photo_url } = await c.req.json();
  if (!id) return c.json({ error: 'id required' }, 400);

  await c.env.DB.prepare(
    `INSERT INTO unassigned_items (id, tenant_id, barcode, description, photo_url, status, logged_by, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, 'pending', ?, datetime('now'), datetime('now'), 1)`
  ).bind(id, tenantId, barcode || null, description || null, photo_url || null, userId).run();

  return c.json({ message: 'Orphaned package logged', id }, 201);
});

warehouseRoutes.get('/consolidate/:customer_id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const customerId = c.req.param('customer_id');
  const items = await c.env.DB.prepare(
    `SELECT oi.*, o.id as order_id FROM order_items oi JOIN orders o ON oi.order_id = o.id
     WHERE o.customer_id = ? AND oi.tenant_id = ? AND oi.status = 'sorted' AND oi.is_deleted = 0`
  ).bind(customerId, tenantId).all();

  return c.json({ customer_id: customerId, items: items.results, total_items: items.results?.length || 0 });
});
