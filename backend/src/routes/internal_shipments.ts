import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt } from '../lib/orderStatus';

export const internalShipmentRoutes = new Hono<AppEnv>();

// GET /internal-shipments — paginated list with order counts
internalShipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page   = parseInt(c.req.query('page')  || '1');
  const limit  = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  const results = await c.env.DB.prepare(`
    SELECT ins.*,
           COUNT(o.id) AS order_count
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
      INSERT INTO internal_shipments (id, tenant_id, delivery_company, notes)
      VALUES (?, ?, ?, ?)
    `).bind(body.id, tenantId, body.delivery_company || null, body.notes || null),
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
           c.full_name  AS customer_name,
           c.phone      AS customer_phone,
           c.city       AS customer_city,
           c.area       AS customer_area,
           COUNT(oi.id) AS item_count
    FROM orders o
    LEFT JOIN customers c  ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id AND oi.is_deleted = 0
    WHERE o.internal_shipment_id = ? AND o.tenant_id = ? AND o.is_deleted = 0
    GROUP BY o.id
  `).bind(id, tenantId).all();

  return c.json({ ...shipment, orders: orders.results });
});

// PATCH /internal-shipments/:id — update status with item-level cascade
// Status pipeline:
//   out_for_delivery → cascade order_items.status = 'dispatched', recompute orders
//   delivered        → cascade order_items.status = 'delivered', recompute orders
//   other            → update shipment only
internalShipmentRoutes.patch('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json();

  const existing = await c.env.DB.prepare(
    `SELECT id FROM internal_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];
  if (body.status           !== undefined) { setClauses.push('status = ?');           values.push(body.status); }
  if (body.delivery_company !== undefined) { setClauses.push('delivery_company = ?'); values.push(body.delivery_company); }
  if (body.notes            !== undefined) { setClauses.push('notes = ?');            values.push(body.notes); }

  const updateShipmentStmt = c.env.DB.prepare(
    `UPDATE internal_shipments SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
  ).bind(...values, id, tenantId);

  if (body.status === 'out_for_delivery' || body.status === 'delivered') {
    const itemStatus = body.status === 'out_for_delivery' ? 'dispatched' : 'delivered';

    // Collect the distinct order_ids that will be touched before modifying
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
        SET status = ?, updated_at = datetime('now'), version = version + 1
        WHERE order_id IN (
          SELECT id FROM orders WHERE internal_shipment_id = ? AND tenant_id = ?
        )
          AND tenant_id = ? AND is_deleted = 0
          AND status NOT IN ('cancelled','refunded','transferred_to_inventory','in_stock')
      `).bind(itemStatus, id, tenantId, tenantId),
      ...recomputeStmts,
    ]);
  } else {
    await updateShipmentStmt.run();
  }

  return c.json({ message: 'Updated', id });
});

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
internalShipmentRoutes.post('/:id/orders/:orderId/return', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const shipmentId = c.req.param('id');
  const orderId = c.req.param('orderId');

  const shipment = await c.env.DB.prepare(
    `SELECT id FROM internal_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(shipmentId, tenantId).first();
  if (!shipment) return c.json({ error: 'Shipment not found' }, 404);

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
  ]);

  return c.json({ message: 'تم تحويل الطلبية للبضاعة الفورية', order_id: orderId });
});
