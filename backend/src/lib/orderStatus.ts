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

/**
 * Recomputes an external shipment's `manual_status` from the receive event:
 *   - 'arrived_at_warehouse' once received_at is set.
 *   - 'in_transit' before receive.
 *
 * Status is NOT inferred from item scans anymore. The prior "derive from
 * items" version created a dead-end where /receive cascaded every shipped
 * item to arrived_warehouse, making the missing count structurally always 0
 * and the mark-lost path unreachable. The correct model: receive is a
 * timestamp ("boxes are physically here"), items are presumed present
 * (arrived_warehouse), the scanner proves presence (sorted), and missing =
 * presumed-present items never proven by a scan.
 *
 * Signature preserved so existing call sites compile untouched.
 */
export function buildRecomputeExternalShipmentStmt(
  db: D1Database,
  shipmentId: string,
  tenantId: string,
): D1PreparedStatement {
  return db.prepare(`
    UPDATE external_shipments
    SET manual_status = CASE
          WHEN received_at IS NULL THEN 'in_transit'
          ELSE 'arrived_at_warehouse'
        END,
        updated_at = datetime('now')
    WHERE id = ? AND tenant_id = ?
  `).bind(shipmentId, tenantId);
}

/**
 * Derives an internal shipment's status from its per-order deliveries:
 *   - 'delivered' when it has at least one attached order and every attached
 *     (non-deleted) order has status = 'delivered'.
 *   - Otherwise leaves the current status alone (pending / out_for_delivery
 *     are still explicit admin transitions).
 *
 * Empty manifests (no attached orders) are NOT auto-completed — flipping a
 * brand-new empty manifest to 'delivered' would be a bug, not a feature.
 * Single UPDATE with two EXISTS subqueries — no loop, no per-order round-trip.
 */
export function buildRecomputeInternalShipmentStmt(
  db: D1Database,
  shipmentId: string,
  tenantId: string,
): D1PreparedStatement {
  return db.prepare(`
    UPDATE internal_shipments
    SET status = CASE
          WHEN EXISTS (
            SELECT 1 FROM orders o
            WHERE o.internal_shipment_id = internal_shipments.id
              AND o.tenant_id = internal_shipments.tenant_id
              AND o.is_deleted = 0
          )
          AND NOT EXISTS (
            SELECT 1 FROM orders o
            WHERE o.internal_shipment_id = internal_shipments.id
              AND o.tenant_id = internal_shipments.tenant_id
              AND o.is_deleted = 0
              AND o.status != 'delivered'
          )
          THEN 'delivered'
          ELSE status
        END,
        updated_at = datetime('now')
    WHERE id = ? AND tenant_id = ?
  `).bind(shipmentId, tenantId);
}
