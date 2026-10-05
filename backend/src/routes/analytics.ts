import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const analyticsRoutes = new Hono<AppEnv>();

/**
 * GET /analytics/dashboard — Dashboard analytics.
 * All queries tenant-scoped with parameterized bindings.
 */
analyticsRoutes.get('/dashboard', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const [
    totalOrdersResult,
    totalCustomersResult,
    totalRevenueResult,
    totalItemsResult,
    statusCountsResult,
    unsortedCountResult,
    readyDispatchCountResult,
    ordersThisWeekResult,
    ordersLastWeekResult,
    revenueThisWeekResult,
    revenueLastWeekResult,
    pendingPurchaseCountResult,
    cashWithDriversResult,
    driverDebtsResult,
  ] = await Promise.all([
    // Total orders
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM orders WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId).first(),

    // Total customers
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM customers WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId).first(),

    // Total revenue — delivered items only
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(oi.unit_price_local * oi.quantity), 0) as total
       FROM order_items oi
       WHERE oi.tenant_id = ? AND oi.is_deleted = 0
         AND oi.status = 'delivered'`
    ).bind(tenantId).first(),

    // Total items
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM order_items WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId).first(),

    // Status counts for order items
    c.env.DB.prepare(
      `SELECT status, COUNT(*) as count FROM order_items
       WHERE tenant_id = ? AND is_deleted = 0
       GROUP BY status`
    ).bind(tenantId).all(),

    // Items needing action: unsorted (purchased/shipped/arrived but not yet sorted)
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM order_items
       WHERE tenant_id = ? AND is_deleted = 0
       AND status IN ('purchased', 'shipped', 'arrived_warehouse')`
    ).bind(tenantId).first(),

    // Items needing action: ready to dispatch
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM order_items
       WHERE tenant_id = ? AND is_deleted = 0
       AND status = 'ready_dispatch'`
    ).bind(tenantId).first(),

    // Orders created in the last 7 days
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM orders
       WHERE tenant_id = ? AND is_deleted = 0
         AND created_at >= datetime('now', '-7 days')`
    ).bind(tenantId).first(),

    // Orders created 8–14 days ago (previous week, for comparison)
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM orders
       WHERE tenant_id = ? AND is_deleted = 0
         AND created_at >= datetime('now', '-14 days')
         AND created_at < datetime('now', '-7 days')`
    ).bind(tenantId).first(),

    // Revenue (delivered) last 7 days
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(oi.unit_price_local * oi.quantity), 0) as total
       FROM order_items oi
       WHERE oi.tenant_id = ? AND oi.is_deleted = 0
         AND oi.status = 'delivered'
         AND oi.updated_at >= datetime('now', '-7 days')`
    ).bind(tenantId).first(),

    // Revenue (delivered) previous week (8–14 days ago)
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(oi.unit_price_local * oi.quantity), 0) as total
       FROM order_items oi
       WHERE oi.tenant_id = ? AND oi.is_deleted = 0
         AND oi.status = 'delivered'
         AND oi.updated_at >= datetime('now', '-14 days')
         AND oi.updated_at < datetime('now', '-7 days')`
    ).bind(tenantId).first(),

    // Items pending purchase (ordered but not yet bought by store)
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM order_items
       WHERE tenant_id = ? AND is_deleted = 0 AND status = 'pending'`
    ).bind(tenantId).first(),

    // Cash sitting with drivers — sum of cash_collected on orders whose
    // manifest has not yet recorded a handover.
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(o.cash_collected), 0) as total
       FROM orders o
       JOIN internal_shipments ins ON ins.id = o.internal_shipment_id
       WHERE o.tenant_id = ? AND o.is_deleted = 0
         AND ins.cash_handed_over IS NULL`
    ).bind(tenantId).first(),

    // Driver debts — a short handover is owed by the driver, not lost
    // revenue. Per driver: SUM(expected − handed_over) over manifests where
    // the handover came up short. expected = SUM(cash_collected) of the
    // manifest's attached orders (same figure the manifest list shows).
    c.env.DB.prepare(
      `SELECT driver_name,
              SUM(cash_expected - cash_handed_over) AS amount,
              COUNT(*) AS manifest_count
       FROM (
         SELECT ins.id,
                COALESCE(NULLIF(TRIM(ins.driver_name), ''), 'غير محدد') AS driver_name,
                ins.cash_handed_over,
                (SELECT COALESCE(SUM(o.cash_collected), 0) FROM orders o
                 WHERE o.internal_shipment_id = ins.id AND o.tenant_id = ins.tenant_id
                   AND o.is_deleted = 0) AS cash_expected
         FROM internal_shipments ins
         WHERE ins.tenant_id = ? AND ins.cash_handed_over IS NOT NULL
       )
       WHERE cash_handed_over < cash_expected
       GROUP BY driver_name
       ORDER BY amount DESC`
    ).bind(tenantId).all(),
  ]);

  // Build status_counts dynamically — no hardcoded stale keys
  const statusCounts: Record<string, number> = {};
  for (const row of (statusCountsResult.results || []) as any[]) {
    statusCounts[row.status] = row.count;
  }

  return c.json({
    total_orders: (totalOrdersResult as any)?.total || 0,
    total_customers: (totalCustomersResult as any)?.total || 0,
    total_revenue_local: (totalRevenueResult as any)?.total || 0,
    total_items: (totalItemsResult as any)?.total || 0,
    status_counts: statusCounts,
    items_needing_action: {
      unsorted: (unsortedCountResult as any)?.total || 0,
      ready_dispatch: (readyDispatchCountResult as any)?.total || 0,
      pending_purchase: (pendingPurchaseCountResult as any)?.total || 0,
      cash_with_drivers: (cashWithDriversResult as any)?.total || 0,
    },
    orders_this_week: (ordersThisWeekResult as any)?.total || 0,
    orders_last_week: (ordersLastWeekResult as any)?.total || 0,
    revenue_this_week: (revenueThisWeekResult as any)?.total || 0,
    revenue_last_week: (revenueLastWeekResult as any)?.total || 0,
    driver_debts: driverDebtsResult.results || [],
  });
});
