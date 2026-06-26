import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const analyticsRoutes = new Hono<AppEnv>();

analyticsRoutes.get('/dashboard', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const [orderStats, topProducts, deliveryStats] = await Promise.all([
    c.env.DB.prepare(
      `SELECT status, COUNT(*) as count FROM orders WHERE tenant_id = ? AND is_deleted = 0 GROUP BY status`
    ).bind(tenantId).all(),
    c.env.DB.prepare(
      `SELECT product_name, SUM(quantity) as total_sold, SUM(unit_price_local * quantity) as total_revenue
       FROM order_items WHERE tenant_id = ? AND is_deleted = 0 GROUP BY product_name ORDER BY total_sold DESC LIMIT 10`
    ).bind(tenantId).all(),
    c.env.DB.prepare(
      `SELECT AVG(julianday(oi.sorted_at) - julianday(oi.created_at)) as avg_days
       FROM order_items oi WHERE oi.tenant_id = ? AND oi.sorted_at IS NOT NULL AND oi.is_deleted = 0`
    ).bind(tenantId).first(),
  ]);

  return c.json({
    order_breakdown: orderStats.results,
    top_products: topProducts.results,
    avg_delivery_days: (deliveryStats as any)?.avg_days || 0,
  });
});
