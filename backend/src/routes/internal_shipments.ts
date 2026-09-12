import { Hono } from 'hono';
import type { AppEnv } from '../types';
import type { Context } from 'hono';
import { requireRole } from '../middleware/tenant';
import {
  buildRecomputeOrderStatusStmt,
  buildRecomputeInternalShipmentStmt,
} from '../lib/orderStatus';

export const internalShipmentRoutes = new Hono<AppEnv>();

/**
 * Ownership check: when the caller is a driver, verify the target manifest's
 * driver_name matches the caller's users.full_name. Returns null on success;
 * on failure returns the JSON response the caller should return directly.
 * No-op for store_manager / super_admin.
 */
async function assertDriverOwnsShipment(
  c: Context<AppEnv>,
  shipmentDriverName: string | null,
): Promise<Response | null> {
  const role = c.get('user_role') as string;
  if (role !== 'driver') return null;
  const userId = c.get('user_id') as string;
  const user = await c.env.DB.prepare(
    `SELECT full_name FROM users WHERE id = ?`
  ).bind(userId).first<{ full_name: string }>();
  const callerName = user?.full_name?.trim() ?? '';
  const driverName = shipmentDriverName?.trim() ?? '';
  if (!callerName || !driverName || callerName !== driverName) {
    return c.json({ error: 'Forbidden', message: 'ليست شحنتك' }, 403);
  }
  return null;
}

// GET /internal-shipments — paginated list with order counts
internalShipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page   = parseInt(c.req.query('page')  || '1');
  const limit  = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  const results = await c.env.DB.prepare(`
    SELECT ins.*,
           COUNT(o.id) AS order_count,
           COALESCE(SUM(o.cash_collected), 0) AS cash_expected
    FROM internal_shipments ins
    LEFT JOIN orders o
           ON o.internal_shipment_id = ins.id AND o.is_deleted = 0
    WHERE ins.tenant_id = ?
    GROUP BY ins.id
    ORDER BY ins.created_at DESC
    LIMIT ? OFFSET ?
  `).bind(tenantId, limit, offset).all();

  return c.json({ data: results.results, page, limit });
});

// GET /internal-shipments/mine — driver's feed of open manifests.
// For role driver: only manifests where driver_name matches the caller's
// users.full_name. For admin roles: every open manifest (so an admin can
// preview what the drivers see). The payload is driver-safe — customer
// contact + address + item names/qtys + expected cash only. NO prices, NO
// cost, NO product URL. Enforced by the explicit SELECT list, not by client-
// side filtering.
internalShipmentRoutes.get(
  '/mine',
  requireRole('driver', 'store_manager', 'super_admin'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const userId = c.get('user_id') as string;
    const role = c.get('user_role') as string;

    let driverFilter = '';
    const args: unknown[] = [tenantId];
    if (role === 'driver') {
      const user = await c.env.DB.prepare(
        `SELECT full_name FROM users WHERE id = ?`
      ).bind(userId).first<{ full_name: string }>();
      const name = user?.full_name?.trim();
      if (!name) return c.json({ data: [] });
      driverFilter = ` AND ins.driver_name = ?`;
      args.push(name);
    }

    const shipments = await c.env.DB.prepare(`
      SELECT ins.id, ins.delivery_company, ins.driver_name, ins.status,
             ins.notes, ins.created_at,
             ins.cash_handed_over, ins.cash_handed_over_at
      FROM internal_shipments ins
      WHERE ins.tenant_id = ?
        AND ins.status IN ('pending', 'out_for_delivery')
        ${driverFilter}
      ORDER BY ins.created_at DESC
    `).bind(...args).all();

    if (!shipments.results.length) return c.json({ data: [] });

    const shipmentIds = shipments.results.map((s) => (s as Record<string, unknown>).id as string);
    const placeholders = shipmentIds.map(() => '?').join(', ');

    // Per-order driver-safe fields + expected cash (sale − deposit).
    // Note the explicit SELECT list — NO unit prices, NO cost fields.
    const orders = await c.env.DB.prepare(`
      SELECT o.id AS order_id, o.status, o.internal_shipment_id,
             o.cash_collected,
             (COALESCE(o.total_sale_price_lyd,
                       (SELECT COALESCE(SUM(COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1)), 0)
                          FROM order_items oi
                          WHERE oi.order_id = o.id
                            AND oi.tenant_id = o.tenant_id
                            AND oi.is_deleted = 0
                            AND oi.status != 'cancelled'),
                       0)
              - COALESCE(o.deposit_amount, 0)) AS expected_cash,
             c.full_name  AS customer_name,
             c.phone      AS customer_phone,
             c.phone2     AS customer_phone2,
             c.city       AS customer_city,
             c.area       AS customer_area,
             c.street     AS customer_street,
             c.address    AS customer_address,
             c.location_url AS customer_location_url
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.internal_shipment_id IN (${placeholders})
        AND o.tenant_id = ?
        AND o.is_deleted = 0
      ORDER BY o.created_at ASC
    `).bind(...shipmentIds, tenantId).all();

    const orderIds = orders.results.map((o) => (o as Record<string, unknown>).order_id as string);
    const itemsByOrder: Record<string, Array<{ product_name: string; quantity: number }>> = {};
    if (orderIds.length > 0) {
      const iPlaceholders = orderIds.map(() => '?').join(', ');
      const items = await c.env.DB.prepare(`
        SELECT oi.order_id, oi.product_name, oi.quantity
        FROM order_items oi
        WHERE oi.order_id IN (${iPlaceholders})
          AND oi.tenant_id = ?
          AND oi.is_deleted = 0
          AND oi.status != 'cancelled'
        ORDER BY oi.created_at ASC
      `).bind(...orderIds, tenantId).all();
      for (const raw of items.results as Array<Record<string, unknown>>) {
        const oid = raw.order_id as string;
        (itemsByOrder[oid] ??= []).push({
          product_name: raw.product_name as string,
          quantity: Number(raw.quantity ?? 1),
        });
      }
    }

    const ordersByShipment: Record<string, Array<Record<string, unknown>>> = {};
    for (const raw of orders.results as Array<Record<string, unknown>>) {
      const sid = raw.internal_shipment_id as string;
      (ordersByShipment[sid] ??= []).push({
        order_id:              raw.order_id,
        status:                raw.status,
        customer_name:         raw.customer_name,
        customer_phone:        raw.customer_phone,
        customer_phone2:       raw.customer_phone2,
        customer_city:         raw.customer_city,
        customer_area:         raw.customer_area,
        customer_street:       raw.customer_street,
        customer_address:      raw.customer_address,
        customer_location_url: raw.customer_location_url,
        expected_cash:         Number(raw.expected_cash ?? 0),
        cash_collected:        Number(raw.cash_collected ?? 0),
        items:                 itemsByOrder[raw.order_id as string] ?? [],
      });
    }

    const data = shipments.results.map((s) => {
      const sid = (s as Record<string, unknown>).id as string;
      return { ...(s as Record<string, unknown>), orders: ordersByShipment[sid] ?? [] };
    });

    return c.json({ data });
  }
);

// GET /internal-shipments/available-orders — orders ready to be added to a manifest
// Eligible: status = 'sorted' or 'ready_dispatch', not yet assigned to an internal shipment
internalShipmentRoutes.get('/available-orders', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(`
    SELECT o.id, o.status, o.created_at,
           c.full_name  AS customer_name,
           c.phone      AS customer_phone,
           c.city       AS customer_city,
           c.area       AS customer_area,
           c.street     AS customer_street,
           COUNT(oi.id) AS item_count
    FROM orders o
    LEFT JOIN customers c  ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id AND oi.is_deleted = 0
    WHERE o.tenant_id = ?
      AND o.status IN ('sorted', 'ready_dispatch')
      AND o.internal_shipment_id IS NULL
      AND o.is_deleted = 0
    GROUP BY o.id
    ORDER BY c.city ASC, c.full_name ASC
  `).bind(tenantId).all();

  return c.json({ data: results.results });
});

// POST /internal-shipments — create manifest; optionally attach initial orders
internalShipmentRoutes.post('/', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  if (!body.id) return c.json({ error: 'id required' }, 400);

  const stmts = [
    c.env.DB.prepare(`
      INSERT INTO internal_shipments (id, tenant_id, delivery_company, driver_name, notes)
      VALUES (?, ?, ?, ?, ?)
    `).bind(body.id, tenantId, body.delivery_company || null, body.driver_name?.trim() || null, body.notes || null),
  ];

  const orderIds: string[] = body.order_ids ?? [];
  for (const orderId of orderIds) {
    stmts.push(
      c.env.DB.prepare(`
        UPDATE orders SET internal_shipment_id = ?, updated_at = datetime('now')
        WHERE id = ? AND tenant_id = ? AND is_deleted = 0
      `).bind(body.id, orderId, tenantId)
    );
  }

  await c.env.DB.batch(stmts);
  return c.json({ message: 'Internal shipment created', id: body.id }, 201);
});

// GET /internal-shipments/:id — detail with linked orders
internalShipmentRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(
    `SELECT * FROM internal_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const orders = await c.env.DB.prepare(`
    SELECT o.id, o.status, o.created_at,
           o.total_sale_price_lyd,
           o.deposit_amount,
           o.deposit_note,
           o.cash_collected,
           o.cash_collected_at,
           c.full_name  AS customer_name,
           c.phone      AS customer_phone,
           c.city       AS customer_city,
           c.area       AS customer_area,
           COUNT(oi.id) AS item_count,
           COALESCE(SUM(COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1)), 0) AS items_sale_total_lyd
    FROM orders o
    LEFT JOIN customers c  ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id AND oi.is_deleted = 0 AND oi.status != 'cancelled'
    WHERE o.internal_shipment_id = ? AND o.tenant_id = ? AND o.is_deleted = 0
    GROUP BY o.id
  `).bind(id, tenantId).all();

  const cashExpected = (orders.results as Record<string, unknown>[]).reduce(
    (sum, o) => sum + Number(o.cash_collected ?? 0),
    0
  );

  return c.json({ ...shipment, cash_expected: cashExpected, orders: orders.results });
});

// PATCH /internal-shipments/:id — admin edits.
// Status pipeline:
//   out_for_delivery → cascade order_items.status = 'dispatched', recompute orders
//   delivered        → REJECTED. The manifest becomes delivered automatically
//                      when every attached order is delivered (via
//                      buildRecomputeInternalShipmentStmt from the per-order
//                      delivered endpoint). This forces the actual event —
//                      per-order confirmation at the door — instead of a
//                      one-click whole-manifest cascade that hid failures.
//   other            → update editable fields only
internalShipmentRoutes.patch('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json();

  if (body.status === 'delivered') {
    return c.json({
      error: 'Bad Request',
      message: 'حالة "تم التسليم" تُحسب تلقائياً — سلّم كل طلبية على حدة',
    }, 400);
  }

  const existing = await c.env.DB.prepare(
    `SELECT id FROM internal_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];
  if (body.status           !== undefined) { setClauses.push('status = ?');           values.push(body.status); }
  if (body.delivery_company !== undefined) { setClauses.push('delivery_company = ?'); values.push(body.delivery_company); }
  if (body.driver_name      !== undefined) { setClauses.push('driver_name = ?');      values.push(body.driver_name?.trim() || null); }
  if (body.notes            !== undefined) { setClauses.push('notes = ?');            values.push(body.notes); }

  const updateShipmentStmt = c.env.DB.prepare(
    `UPDATE internal_shipments SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
  ).bind(...values, id, tenantId);

  if (body.status === 'out_for_delivery') {
    // Cascade attached-order items to 'dispatched' and recompute each order.
    const affected = await c.env.DB.prepare(`
      SELECT DISTINCT id FROM orders
      WHERE internal_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, tenantId).all();
    const orderIds = affected.results.map((r) => (r as Record<string, unknown>).id as string);

    const recomputeStmts = orderIds.map((oid) => buildRecomputeOrderStatusStmt(c.env.DB, oid, tenantId));
    await c.env.DB.batch([
      updateShipmentStmt,
      c.env.DB.prepare(`
        UPDATE order_items
        SET status = 'dispatched', updated_at = datetime('now'), version = version + 1
        WHERE order_id IN (
          SELECT id FROM orders WHERE internal_shipment_id = ? AND tenant_id = ?
        )
          AND tenant_id = ? AND is_deleted = 0
          AND status NOT IN ('cancelled','refunded','transferred_to_inventory','in_stock')
      `).bind(id, tenantId, tenantId),
      ...recomputeStmts,
    ]);
  } else {
    await updateShipmentStmt.run();
  }

  return c.json({ message: 'Updated', id });
});

// PATCH /internal-shipments/:id/orders/:orderId/delivered — the event that
// actually happens at the door. Cascades this ONE order's live items to
// 'delivered', seeds cash_collected = sale − deposit (unless body overrides),
// recomputes the order, then recomputes the manifest (which flips to
// 'delivered' once every attached order is done).
//
// Driver can call it for manifests where driver_name matches their full_name.
internalShipmentRoutes.patch(
  '/:id/orders/:orderId/delivered',
  requireRole('driver', 'store_manager', 'super_admin'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const shipmentId = c.req.param('id')!;
    const orderId = c.req.param('orderId')!;
    const body = await c.req.json<{ cash_collected?: number }>().catch(() => ({} as { cash_collected?: number }));

    const shipment = await c.env.DB.prepare(
      `SELECT id, driver_name FROM internal_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(shipmentId, tenantId).first<{ id: string; driver_name: string | null }>();
    if (!shipment) return c.json({ error: 'Not Found' }, 404);

    const denied = await assertDriverOwnsShipment(c, shipment.driver_name);
    if (denied) return denied;

    const order = await c.env.DB.prepare(
      `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND internal_shipment_id = ? AND is_deleted = 0`
    ).bind(orderId, tenantId, shipmentId).first();
    if (!order) return c.json({ error: 'Not Found', message: 'Order not on this manifest' }, 404);

    let cashOverride: number | null = null;
    if (body && body.cash_collected !== undefined && body.cash_collected !== null) {
      const n = Number(body.cash_collected);
      if (isNaN(n) || n < 0) {
        return c.json({ error: 'Bad Request', message: 'cash_collected لا يمكن أن يكون سالباً' }, 400);
      }
      cashOverride = n;
    }

    const batchStmts: D1PreparedStatement[] = [
      c.env.DB.prepare(`
        UPDATE order_items
        SET status = 'delivered', updated_at = datetime('now'), version = version + 1
        WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0
          AND status NOT IN ('cancelled','refunded','transferred_to_inventory','in_stock')
      `).bind(orderId, tenantId),
    ];

    if (cashOverride !== null) {
      batchStmts.push(c.env.DB.prepare(`
        UPDATE orders
        SET cash_collected = ?, cash_collected_at = datetime('now'), updated_at = datetime('now')
        WHERE id = ? AND tenant_id = ?
      `).bind(cashOverride, orderId, tenantId));
    } else {
      // Same expression as the bulk delivery cascade: sale − deposit, floored at 0.
      // Only seeds when cash_collected is still 0 so we don't overwrite an earlier
      // per-order cash correction.
      batchStmts.push(c.env.DB.prepare(`
        UPDATE orders
        SET cash_collected = MAX(
              COALESCE(orders.total_sale_price_lyd,
                       (SELECT COALESCE(SUM(COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1)), 0)
                          FROM order_items oi
                          WHERE oi.order_id = orders.id
                            AND oi.tenant_id = orders.tenant_id
                            AND oi.is_deleted = 0
                            AND oi.status != 'cancelled'),
                       0)
              - COALESCE(orders.deposit_amount, 0),
              0
            ),
            cash_collected_at = datetime('now'),
            updated_at = datetime('now')
        WHERE id = ? AND tenant_id = ? AND cash_collected = 0
      `).bind(orderId, tenantId));
    }

    batchStmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
    batchStmts.push(buildRecomputeInternalShipmentStmt(c.env.DB, shipmentId, tenantId));

    await c.env.DB.batch(batchStmts);
    return c.json({ message: 'Order delivered', order_id: orderId });
  }
);

// PATCH /internal-shipments/:id/orders/:orderId/cash
// Correct the cash_collected for a single order on this manifest.
// Used when the driver returned a partial payment or a door discount was given.
internalShipmentRoutes.patch(
  '/:id/orders/:orderId/cash',
  requireRole('super_admin', 'store_manager'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const shipmentId = c.req.param('id');
    const orderId = c.req.param('orderId');
    const body = await c.req.json<{ cash_collected: number }>();

    if (body.cash_collected === undefined || body.cash_collected === null || isNaN(Number(body.cash_collected))) {
      return c.json({ error: 'Bad Request', message: 'cash_collected is required (number)' }, 400);
    }
    if (Number(body.cash_collected) < 0) {
      return c.json({ error: 'Bad Request', message: 'cash_collected لا يمكن أن يكون سالباً' }, 400);
    }

    const order = await c.env.DB.prepare(
      `SELECT id FROM orders
       WHERE id = ? AND tenant_id = ? AND internal_shipment_id = ? AND is_deleted = 0`
    ).bind(orderId, tenantId, shipmentId).first();
    if (!order) return c.json({ error: 'Not Found', message: 'Order not on this manifest' }, 404);

    await c.env.DB.prepare(
      `UPDATE orders
       SET cash_collected = ?, cash_collected_at = datetime('now'), updated_at = datetime('now')
       WHERE id = ? AND tenant_id = ?`
    ).bind(Number(body.cash_collected), orderId, tenantId).run();

    return c.json({ message: 'Updated', id: orderId, cash_collected: Number(body.cash_collected) });
  }
);

// PATCH /internal-shipments/:id/handover — driver hands cash back to the store
// Returns the expected total (sum of cash_collected on the manifest) so the UI
// can show a shortfall/surplus vs. what was handed over.
internalShipmentRoutes.patch(
  '/:id/handover',
  requireRole('super_admin', 'store_manager'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const id = c.req.param('id');
    const body = await c.req.json<{ cash_handed_over: number }>();

    if (body.cash_handed_over === undefined || body.cash_handed_over === null || isNaN(Number(body.cash_handed_over))) {
      return c.json({ error: 'Bad Request', message: 'cash_handed_over is required (number)' }, 400);
    }
    if (Number(body.cash_handed_over) < 0) {
      return c.json({ error: 'Bad Request', message: 'cash_handed_over لا يمكن أن يكون سالباً' }, 400);
    }

    const shipment = await c.env.DB.prepare(
      `SELECT id FROM internal_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(id, tenantId).first();
    if (!shipment) return c.json({ error: 'Not Found' }, 404);

    const expectedRow = await c.env.DB.prepare(
      `SELECT COALESCE(SUM(cash_collected), 0) AS cash_expected
       FROM orders
       WHERE internal_shipment_id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(id, tenantId).first();
    const cashExpected = Number((expectedRow as Record<string, unknown>)?.cash_expected ?? 0);

    await c.env.DB.prepare(
      `UPDATE internal_shipments
       SET cash_handed_over = ?, cash_handed_over_at = datetime('now'), updated_at = datetime('now')
       WHERE id = ? AND tenant_id = ?`
    ).bind(Number(body.cash_handed_over), id, tenantId).run();

    return c.json({
      message: 'Handover recorded',
      id,
      cash_handed_over: Number(body.cash_handed_over),
      cash_expected: cashExpected,
      difference: Number(body.cash_handed_over) - cashExpected,
    });
  }
);

// POST /internal-shipments/:id/attach — add more orders to an existing manifest
internalShipmentRoutes.post('/:id/attach', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const { order_ids } = await c.req.json<{ order_ids: string[] }>();
  if (!order_ids?.length) return c.json({ error: 'order_ids required' }, 400);

  const shipment = await c.env.DB.prepare(
    `SELECT id FROM internal_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const stmts = order_ids.map((orderId) =>
    c.env.DB.prepare(`
      UPDATE orders SET internal_shipment_id = ?, updated_at = datetime('now')
      WHERE id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, orderId, tenantId)
  );

  await c.env.DB.batch(stmts);
  return c.json({ message: `${order_ids.length} orders attached`, shipment_id: id });
});

// DELETE /internal-shipments/:id — detach all orders then delete
internalShipmentRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE orders SET internal_shipment_id = NULL, updated_at = datetime('now')
      WHERE internal_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, tenantId),
    c.env.DB.prepare(
      `DELETE FROM internal_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(id, tenantId),
  ]);

  return c.json({ message: 'Internal shipment deleted', id });
});

// POST /internal-shipments/:id/orders/:orderId/return
// Orphans all non-terminal items → in_stock, cancels the order, detaches from manifest.
// Drivers can call this at the door (with ownership check).
internalShipmentRoutes.post(
  '/:id/orders/:orderId/return',
  requireRole('driver', 'store_manager', 'super_admin'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const shipmentId = c.req.param('id')!;
    const orderId = c.req.param('orderId')!;

    const shipment = await c.env.DB.prepare(
      `SELECT id, driver_name FROM internal_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(shipmentId, tenantId).first<{ id: string; driver_name: string | null }>();
    if (!shipment) return c.json({ error: 'Shipment not found' }, 404);

    const denied = await assertDriverOwnsShipment(c, shipment.driver_name);
    if (denied) return denied;

    const order = await c.env.DB.prepare(
      `SELECT id FROM orders WHERE id = ? AND tenant_id = ? AND internal_shipment_id = ? AND is_deleted = 0`
    ).bind(orderId, tenantId, shipmentId).first();
    if (!order) return c.json({ error: 'Order not found in this shipment' }, 404);

    await c.env.DB.batch([
      // Orphan all non-terminal items → available as instant stock
      c.env.DB.prepare(`
        UPDATE order_items
        SET order_id = NULL, status = 'in_stock',
            updated_at = datetime('now'), version = version + 1
        WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0
          AND status NOT IN ('cancelled','refunded','transferred_to_inventory','in_stock')
      `).bind(orderId, tenantId),
      // Cancel the order and detach from manifest
      c.env.DB.prepare(`
        UPDATE orders
        SET internal_shipment_id = NULL, status = 'cancelled',
            updated_at = datetime('now'), version = version + 1
        WHERE id = ? AND tenant_id = ?
      `).bind(orderId, tenantId),
      // Detaching the order may complete the manifest (all remaining orders
      // already delivered), so recompute the manifest status.
      buildRecomputeInternalShipmentStmt(c.env.DB, shipmentId, tenantId),
    ]);

    return c.json({ message: 'تم تحويل الطلبية للبضاعة الفورية', order_id: orderId });
  }
);
