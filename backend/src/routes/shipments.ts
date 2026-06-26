import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const shipmentRoutes = new Hono<AppEnv>();

/**
 * GET /shipments — List shipments for tenant
 */
shipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  const results = await c.env.DB.prepare(
    `SELECT * FROM shipments WHERE tenant_id = ? AND is_deleted = 0 
     ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).bind(tenantId, limit, offset).all();

  return c.json({ data: results.results, page, limit });
});

/**
 * POST /shipments — Create a shipment (composite key: tracking + supplier + date)
 */
shipmentRoutes.post('/', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const body = await c.req.json();

  const { id, tracking_number, supplier_id, ship_date, master_shipment_id, items } = body;

  if (!id || !tracking_number || !supplier_id || !ship_date) {
    return c.json({ error: 'Bad Request', message: 'id, tracking_number, supplier_id, and ship_date are required' }, 400);
  }

  const stmts: D1PreparedStatement[] = [];

  stmts.push(
    c.env.DB.prepare(
      `INSERT INTO shipments (id, tenant_id, tracking_number, supplier_id, ship_date,
       master_shipment_id, status, created_by, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, ?, 'in_transit', ?, datetime('now'), datetime('now'), 1)`
    ).bind(id, tenantId, tracking_number, supplier_id, ship_date,
           master_shipment_id || null, userId)
  );

  // Link items to this shipment
  if (items?.length) {
    for (const itemId of items) {
      stmts.push(
        c.env.DB.prepare(
          `UPDATE order_items SET shipment_id = ?, status = 'shipped', updated_at = datetime('now')
           WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
        ).bind(id, itemId, tenantId)
      );
    }
  }

  await c.env.DB.batch(stmts);
  return c.json({ message: 'Shipment created', id }, 201);
});

/**
 * POST /shipments/master — Create a master shipment
 */
shipmentRoutes.post('/master', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const body = await c.req.json();

  const { id, name, customs_cost, freight_cost, notes } = body;

  if (!id || !name) {
    return c.json({ error: 'Bad Request', message: 'id and name are required' }, 400);
  }

  await c.env.DB.prepare(
    `INSERT INTO master_shipments (id, tenant_id, name, customs_cost, freight_cost, 
     notes, status, created_by, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, datetime('now'), datetime('now'), 1)`
  ).bind(id, tenantId, name, customs_cost || 0, freight_cost || 0,
         notes || null, userId).run();

  return c.json({ message: 'Master shipment created', id }, 201);
});

/**
 * PATCH /shipments/master/:id/arrive — Arrive a master shipment (cascades to all nested)
 */
shipmentRoutes.patch('/master/:id/arrive', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const masterId = c.req.param('id');
  const body = await c.req.json();
  const { version } = body;

  if (!version) {
    return c.json({ error: 'Bad Request', message: 'version required for OCC' }, 400);
  }

  // Update master shipment
  const masterResult = await c.env.DB.prepare(
    `UPDATE master_shipments SET status = 'arrived', version = version + 1, updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(masterId, tenantId, version).run();

  if (masterResult.meta.changes === 0) {
    return c.json({ error: 'Conflict', message: 'Version mismatch or not found' }, 409);
  }

  // Cascade: update all nested shipments
  await c.env.DB.prepare(
    `UPDATE shipments SET status = 'arrived', updated_at = datetime('now')
     WHERE master_shipment_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(masterId, tenantId).run();

  // Cascade: update all items in those shipments
  await c.env.DB.prepare(
    `UPDATE order_items SET status = 'arrived_warehouse', updated_at = datetime('now')
     WHERE shipment_id IN (
       SELECT id FROM shipments WHERE master_shipment_id = ? AND tenant_id = ?
     ) AND tenant_id = ? AND is_deleted = 0`
  ).bind(masterId, tenantId, tenantId).run();

  return c.json({ message: 'Master shipment arrived — all nested items updated', id: masterId });
});
