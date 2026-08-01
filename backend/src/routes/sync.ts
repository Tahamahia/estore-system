import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const syncRoutes = new Hono<AppEnv>();

/**
 * GET /sync — Lightweight polling endpoint for real-time UI updates
 *
 * Free-tier friendly: No Durable Objects required.
 * Flutter polls this every 10-15 seconds via Riverpod timer.
 *
 * Returns a compact changeset: counts, timestamps, and dirty flags
 * so the client knows which data to re-fetch without full page reloads.
 *
 * Response is < 500 bytes — minimal bandwidth.
 */
syncRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id');
  const since = c.req.query('since');

  const [orderStats, changedOrders, customerStats, itemStats] = await Promise.all([
    // Order counts using current status enum
    c.env.DB.prepare(`
      SELECT COUNT(*) as total_orders,
        SUM(CASE WHEN status = 'pending'       THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'purchased'     THEN 1 ELSE 0 END) as purchased,
        SUM(CASE WHEN status = 'shipped'       THEN 1 ELSE 0 END) as shipped,
        SUM(CASE WHEN status = 'delivered'     THEN 1 ELSE 0 END) as delivered,
        MAX(updated_at) as last_order_update
      FROM orders WHERE tenant_id = ? AND is_deleted = 0
    `).bind(tenantId).first(),

    // Changed orders since last sync
    c.env.DB.prepare(`
      SELECT COUNT(*) as changed_orders
      FROM orders WHERE tenant_id = ? AND is_deleted = 0 AND updated_at > ?
    `).bind(tenantId, since || '1970-01-01T00:00:00Z').first(),

    // Customer count
    c.env.DB.prepare(`
      SELECT COUNT(*) as total_customers FROM customers
      WHERE tenant_id = ? AND is_deleted = 0
    `).bind(tenantId).first(),

    // Action items
    c.env.DB.prepare(`
      SELECT
        SUM(CASE WHEN status IN ('purchased','shipped','arrived_warehouse') THEN 1 ELSE 0 END) as unsorted,
        SUM(CASE WHEN status = 'ready_dispatch' THEN 1 ELSE 0 END) as ready_dispatch,
        SUM(CASE WHEN status = 'in_stock' AND order_id IS NULL THEN 1 ELSE 0 END) as in_stock_count
      FROM order_items WHERE tenant_id = ? AND is_deleted = 0
    `).bind(tenantId).first(),
  ]);

  type Row = Record<string, unknown>;
  const orders   = (orderStats   || {}) as Row;
  const changed  = (changedOrders || {}) as Row;
  const customers = (customerStats || {}) as Row;
  const items    = (itemStats    || {}) as Row;

  return c.json({
    server_time: new Date().toISOString(),
    dirty: (changed.changed_orders as number || 0) > 0,
    orders: {
      total:       orders.total_orders   || 0,
      pending:     orders.pending        || 0,
      purchased:   orders.purchased      || 0,
      shipped:     orders.shipped        || 0,
      delivered:   orders.delivered      || 0,
      last_update: orders.last_order_update || null,
    },
    customers: { total: customers.total_customers || 0 },
    action_items: {
      unsorted:       items.unsorted       || 0,
      ready_dispatch: items.ready_dispatch || 0,
      in_stock:       items.in_stock_count || 0,
    },
  });
});
