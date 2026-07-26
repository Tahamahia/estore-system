import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const analyticsRoutes = new Hono<AppEnv>();

/**
 * GET /analytics/dashboard — Comprehensive dashboard analytics
 * Returns totals, status breakdown, recent orders, top customers, and action items.
 * All queries are tenant-scoped with parameterized bindings.
 */
analyticsRoutes.get('/dashboard', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const [
    totalOrdersResult,
    totalCustomersResult,
    totalRevenueResult,
    totalItemsResult,
    statusCountsResult,
    recentOrdersResult,
    topCustomersResult,
    unsortedCountResult,
    readyDispatchCountResult,
  ] = await Promise.all([
    // Total orders
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM orders WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId).first(),

    // Total customers
    c.env.DB.prepare(
      `SELECT COUNT(*) as total FROM customers WHERE tenant_id = ? AND is_deleted = 0`
    ).bind(tenantId).first(),

    // Total revenue (local currency)
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(oi.unit_price_local * oi.quantity), 0) as total
       FROM order_items oi
       WHERE oi.tenant_id = ? AND oi.is_deleted = 0`
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

    // Recent orders (top 10 with customer name)
    c.env.DB.prepare(
      `SELECT o.id, o.status, o.platform, o.currency, o.created_at, o.updated_at,
              c.full_name as customer_name, c.id as customer_id
       FROM orders o
       LEFT JOIN customers c ON o.customer_id = c.id
       WHERE o.tenant_id = ? AND o.is_deleted = 0
       ORDER BY o.created_at DESC
       LIMIT 10`
    ).bind(tenantId).all(),

    // Top 5 customers by order count
    c.env.DB.prepare(
      `SELECT c.id, c.full_name, c.phone, COUNT(o.id) as order_count
       FROM customers c
       JOIN orders o ON c.id = o.customer_id
       WHERE c.tenant_id = ? AND c.is_deleted = 0 AND o.is_deleted = 0
       GROUP BY c.id
       ORDER BY order_count DESC
       LIMIT 5`
    ).bind(tenantId).all(),

    // Items needing action: unsorted (arrived but not sorted)
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
  ]);

  // Build status_counts as a flat object
  const statusCounts: Record<string, number> = {
    pending_payment: 0,
    purchased: 0,
    shipped: 0,
    arrived_warehouse: 0,
    sorted: 0,
    ready_dispatch: 0,
    dispatched: 0,
    delivered: 0,
  };
  for (const row of (statusCountsResult.results || []) as any[]) {
    statusCounts[row.status] = row.count;
  }

  return c.json({
    total_orders: (totalOrdersResult as any)?.total || 0,
    total_customers: (totalCustomersResult as any)?.total || 0,
    total_revenue_local: (totalRevenueResult as any)?.total || 0,
    total_items: (totalItemsResult as any)?.total || 0,
    status_counts: statusCounts,
    recent_orders: recentOrdersResult.results || [],
    top_customers: topCustomersResult.results || [],
    items_needing_action: {
      unsorted: (unsortedCountResult as any)?.total || 0,
      ready_to_dispatch: (readyDispatchCountResult as any)?.total || 0,
    },
  });
});
