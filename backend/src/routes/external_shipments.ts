import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const externalShipmentRoutes = new Hono<AppEnv>();

// Mock tracking service — simulates 17TRACK / TrackingMore API response
async function syncTrackingAPI(trackingNumber: string): Promise<{
  courier: string;
  status: string;
  lastEvent: string;
  lastLocation: string;
}> {
  const tn = trackingNumber.toUpperCase();
  let courier = 'Unknown Courier';
  // J&T Express — used by Shein for most international parcels (JTE prefix)
  if (tn.startsWith('JTE'))                                courier = 'J&T Express (Shein)';
  // Shein Global Logistics (GSH prefix)
  else if (tn.startsWith('GSH'))                           courier = 'Shein Global Logistics';
  // YunExpress — common Shein/AliExpress carrier (YT prefix)
  else if (tn.startsWith('YT'))                            courier = 'YunExpress';
  // AliExpress Standard Shipping (LP prefix)
  else if (tn.startsWith('LP'))                            courier = 'AliExpress Standard';
  // EMS / ePacket (EX or EE prefix)
  else if (tn.startsWith('EX') || tn.startsWith('EE'))     courier = 'EMS';
  // JD Logistics (JD prefix — distinct from JTE above)
  else if (tn.startsWith('JD'))                            courier = 'JD Logistics';
  // SF Express
  else if (tn.startsWith('SF'))                            courier = 'SF Express';
  // Trendyol Express
  else if (tn.startsWith('TY') || tn.startsWith('TRY'))   courier = 'Trendyol Express';
  // Cainiao / AliExpress logistics
  else if (tn.startsWith('CA') || tn.startsWith('CN'))     courier = 'Cainiao';
  // UPS
  else if (tn.startsWith('1Z'))                            courier = 'UPS';
  // DHL (22-digit all-numeric)
  else if (/^[0-9]{20,22}$/.test(tn))                     courier = 'DHL';
  // FedEx (12–14-digit all-numeric)
  else if (/^[0-9]{12,14}$/.test(tn))                     courier = 'FedEx';
  // Legacy Shein SH/SG prefixes
  else if (tn.startsWith('SH') || tn.startsWith('SG'))    courier = 'Shein Logistics';

  const hash = trackingNumber.split('').reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  const stages = [
    { status: 'departed_origin',      event: 'Parcel collected from seller',       location: 'Guangzhou, CN' },
    { status: 'in_transit',           event: 'In transit at sorting hub',           location: 'Shanghai, CN' },
    { status: 'departed_country',     event: 'Departed origin country',             location: 'Beijing, CN' },
    { status: 'arrived_destination',  event: 'Arrived at destination country',      location: 'Tripoli, LY' },
    { status: 'customs_clearance',    event: 'Clearance in progress',               location: 'Tripoli Port, LY' },
    { status: 'out_for_delivery',     event: 'Out for final-mile delivery',          location: 'Tripoli, LY' },
  ];
  const stage = stages[hash % stages.length];

  return { courier, status: stage.status, lastEvent: stage.event, lastLocation: stage.location };
}

// GET /external-shipments — paginated list with item counts
externalShipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page   = parseInt(c.req.query('page')  || '1');
  const limit  = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  const results = await c.env.DB.prepare(`
    SELECT es.*,
           COUNT(oi.id) AS item_count
    FROM external_shipments es
    LEFT JOIN order_items oi
           ON oi.external_shipment_id = es.id AND oi.is_deleted = 0
    WHERE es.tenant_id = ?
    GROUP BY es.id
    ORDER BY es.created_at DESC
    LIMIT ? OFFSET ?
  `).bind(tenantId, limit, offset).all();

  return c.json({ data: results.results, page, limit });
});

// GET /external-shipments/available-items — items eligible for attachment
// (status = 'purchased', not yet linked to any external shipment)
externalShipmentRoutes.get('/available-items', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(`
    SELECT oi.id, oi.product_name, oi.sku, oi.item_uid, oi.status,
           oi.quantity, oi.order_id,
           c.full_name AS customer_name
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    LEFT JOIN customers c ON o.customer_id = c.id
    WHERE oi.tenant_id = ?
      AND oi.status = 'purchased'
      AND oi.external_shipment_id IS NULL
      AND oi.is_deleted = 0
    ORDER BY oi.created_at DESC
  `).bind(tenantId).all();

  return c.json({ data: results.results });
});

// POST /external-shipments — create
externalShipmentRoutes.post('/', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  if (!body.id) return c.json({ error: 'id required' }, 400);

  await c.env.DB.prepare(`
    INSERT INTO external_shipments (id, tenant_id, tracking_number, courier_code, notes)
    VALUES (?, ?, ?, ?, ?)
  `).bind(body.id, tenantId, body.tracking_number || null, body.courier_code || null, body.notes || null).run();

  return c.json({ message: 'External shipment created', id: body.id }, 201);
});

// GET /external-shipments/:id — detail with linked items
externalShipmentRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(
    `SELECT * FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const items = await c.env.DB.prepare(`
    SELECT oi.id, oi.product_name, oi.sku, oi.item_uid, oi.status,
           oi.quantity, oi.order_id,
           c.full_name AS customer_name
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    LEFT JOIN customers c ON o.customer_id = c.id
    WHERE oi.external_shipment_id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0
  `).bind(id, tenantId).all();

  return c.json({ ...shipment, items: items.results });
});

// PATCH /external-shipments/:id — update; cascade to items on arrived_at_warehouse
externalShipmentRoutes.patch('/:id', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json();

  const existing = await c.env.DB.prepare(
    `SELECT id FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];
  if (body.manual_status !== undefined) { setClauses.push('manual_status = ?'); values.push(body.manual_status); }
  if (body.courier_code  !== undefined) { setClauses.push('courier_code = ?');  values.push(body.courier_code); }
  if (body.notes         !== undefined) { setClauses.push('notes = ?');         values.push(body.notes); }
  if (body.api_status    !== undefined) { setClauses.push('api_status = ?');    values.push(body.api_status); }

  if (setClauses.length === 1) return c.json({ error: 'No fields to update' }, 400);

  if (body.manual_status === 'arrived_at_warehouse') {
    await c.env.DB.batch([
      c.env.DB.prepare(
        `UPDATE external_shipments SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
      ).bind(...values, id, tenantId),
      c.env.DB.prepare(`
        UPDATE order_items
        SET status = 'arrived_warehouse', updated_at = datetime('now'), version = version + 1
        WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
          AND status NOT IN ('cancelled', 'refunded')
      `).bind(id, tenantId),
    ]);
  } else {
    await c.env.DB.prepare(
      `UPDATE external_shipments SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
    ).bind(...values, id, tenantId).run();
  }

  return c.json({ message: 'Updated', id });
});

// POST /external-shipments/:id/sync — call mock tracking API
externalShipmentRoutes.post('/:id/sync', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(
    `SELECT * FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first() as Record<string, unknown> | null;
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const trackingNumber = shipment.tracking_number as string | null;
  if (!trackingNumber) return c.json({ error: 'No tracking number on this shipment' }, 400);

  const tracking = await syncTrackingAPI(trackingNumber);

  await c.env.DB.prepare(
    `UPDATE external_shipments SET api_status = ?, courier_code = ?, updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ?`
  ).bind(tracking.status, tracking.courier, id, tenantId).run();

  return c.json({ message: 'Tracking synced', tracking });
});

// POST /external-shipments/:id/attach — link order items, advance status to 'shipped'
externalShipmentRoutes.post('/:id/attach', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const { item_ids } = await c.req.json<{ item_ids: string[] }>();
  if (!item_ids?.length) return c.json({ error: 'item_ids required' }, 400);

  const shipment = await c.env.DB.prepare(
    `SELECT id FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const stmts = item_ids.map((itemId) =>
    c.env.DB.prepare(`
      UPDATE order_items
      SET external_shipment_id = ?, status = 'shipped',
          updated_at = datetime('now'), version = version + 1
      WHERE id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, itemId, tenantId)
  );

  await c.env.DB.batch(stmts);
  return c.json({ message: `${item_ids.length} items attached to shipment`, shipment_id: id });
});

// DELETE /external-shipments/:id — detach items (reset to purchased) then delete
externalShipmentRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE order_items
      SET external_shipment_id = NULL, status = 'purchased', updated_at = datetime('now')
      WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, tenantId),
    c.env.DB.prepare(
      `DELETE FROM external_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(id, tenantId),
  ]);

  return c.json({ message: 'External shipment deleted', id });
});
