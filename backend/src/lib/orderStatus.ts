/**
 * Recomputes an order's status as the earliest (furthest-behind) status among
 * its non-deleted items.  Cancelled / refunded / transferred_to_inventory /
 * in_stock are treated as priority 8 (same tier as delivered) so a single
 * unavailable item never drags the whole order's displayed status backward.
 * If the order has zero live items, COALESCE leaves the status untouched.
 */
export function buildRecomputeOrderStatusStmt(
  db: D1Database,
  orderId: string,
  tenantId: string,
): D1PreparedStatement {
  return db.prepare(`
    UPDATE orders
    SET status = COALESCE((
          SELECT oi.status FROM order_items oi
          WHERE oi.order_id = orders.id
            AND oi.tenant_id = orders.tenant_id
            AND oi.is_deleted = 0
          ORDER BY CASE oi.status
            WHEN 'pending'            THEN 0
            WHEN 'purchased'          THEN 1
            WHEN 'shipped'            THEN 2
            WHEN 'arrived_warehouse'  THEN 3
            WHEN 'sorted'             THEN 4
            WHEN 'ready_dispatch'     THEN 5
            WHEN 'dispatched'         THEN 6
            WHEN 'delivered'          THEN 7
            ELSE 8 END ASC
          LIMIT 1
        ), status),
        version    = version + 1,
        updated_at = datetime('now')
    WHERE id = ? AND tenant_id = ?
  `).bind(orderId, tenantId);
}
