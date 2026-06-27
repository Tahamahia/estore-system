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
  const since = c.req.query('since');  // ISO timestamp or null

  // Build a lightweight sync snapshot
  const queries = [
    // Order counts by status
    c.env.DB.prepare(
      `SELECT 
         COUNT(*) as total_orders,
         SUM(CASE WHEN status = 'pending_payment' THEN 1 ELSE 0 END) as pending,
         SUM(CASE WHEN status = 'purchased' THEN 1 ELSE 0 END) as purchased,
         SUM(CASE WHEN status = 'shipped' THEN 1 ELSE 0 END) as shipped,
         SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) as delivered,
         MAX(updated_at) as last_order_update
       FROM orders WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId),
    // Recent changes since last sync
    c.env.DB.prepare(
      `SELECT COUNT(*) as changed_orders
       FROM orders WHERE tenant_id = ? AND is_deleted = 0 AND updated_at > ?`
    ).bind(tenantId, since || '1970-01-01T00:00:00Z'),
    // Customer count
    c.env.DB.prepare(
      `SELECT COUNT(*) as total_customers FROM customers
       WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId),
    // Shipment counts
    c.env.DB.prepare(
      `SELECT 
         COUNT(*) as total_shipments,
         SUM(CASE WHEN status = 'in_transit' THEN 1 ELSE 0 END) as in_transit,
         MAX(updated_at) as last_shipment_update
       FROM shipments WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId),
    // Unassigned items (orphans)
    c.env.DB.prepare(
      `SELECT COUNT(*) as orphan_count FROM unassigned_items
       WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId),
  ];

  const [orderStats, changedOrders, customerStats, shipmentStats, orphanStats] =
    await c.env.DB.batch(queries);

  type Row = Record<string, unknown>;
  const orders = (orderStats.results?.[0] || {}) as Row;
  const changed = (changedOrders.results?.[0] || {}) as Row;
  const customers = (customerStats.results?.[0] || {}) as Row;
  const shipments = (shipmentStats.results?.[0] || {}) as Row;
  const orphans = (orphanStats.results?.[0] || {}) as Row;

  // Dirty flags: tell the client which sections need re-fetching
  const hasChanges = (changed.changed_orders as number || 0) > 0;

  return c.json({
    server_time: new Date().toISOString(),
    dirty: hasChanges,
    orders: {
      total: orders.total_orders || 0,
      pending: orders.pending || 0,
      purchased: orders.purchased || 0,
      shipped: orders.shipped || 0,
      delivered: orders.delivered || 0,
      last_update: orders.last_order_update || null,
    },
    customers: {
      total: customers.total_customers || 0,
    },
    shipments: {
      total: shipments.total_shipments || 0,
      in_transit: shipments.in_transit || 0,
      last_update: shipments.last_shipment_update || null,
    },
    orphans: {
      count: orphans.orphan_count || 0,
    },
  });
});
