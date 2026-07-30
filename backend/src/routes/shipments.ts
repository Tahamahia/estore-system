import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const shipmentRoutes = new Hono<AppEnv>();

/** GET /shipments — list all shipments for the tenant */
shipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const results = await c.env.DB.prepare(
    `SELECT * FROM shipments WHERE tenant_id = ? AND is_deleted = 0 ORDER BY created_at DESC`
  ).bind(tenantId).all();
  return c.json({ data: results.results });
});

/** POST /shipments — create a new shipment */
shipmentRoutes.post('/', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json<{ id?: string; name?: string; notes?: string }>();
  const { id, name, notes } = body;

  if (!id || !name?.trim()) {
    return c.json({ error: 'id and name are required' }, 400);
  }

  await c.env.DB.prepare(
    `INSERT INTO shipments (id, tenant_id, name, status, notes, created_at, updated_at, version)
     VALUES (?, ?, ?, 'pending', ?, datetime('now'), datetime('now'), 1)`
  ).bind(id, tenantId, name.trim(), notes ?? null).run();

  return c.json({ message: 'Shipment created', id }, 201);
});

/** PATCH /shipments/:id — update name / status / notes */
shipmentRoutes.patch('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const shipmentId = c.req.param('id');
  const body = await c.req.json();
  const { version, ...updates } = body;

  if (!version) return c.json({ error: 'version required for OCC' }, 400);

  const allowed = ['name', 'status', 'notes'];
  const setClauses: string[] = [];
  const values: unknown[] = [];

  for (const field of allowed) {
    if (updates[field] !== undefined) {
      setClauses.push(`${field} = ?`);
      values.push(updates[field] === '' ? null : updates[field]);
    }
  }

  if (!setClauses.length) return c.json({ error: 'No valid fields to update' }, 400);

  setClauses.push(`version = version + 1`, `updated_at = datetime('now')`);

  const result = await c.env.DB.prepare(
    `UPDATE shipments SET ${setClauses.join(', ')}
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, shipmentId, tenantId, version).run();

  if ((result.meta.changes ?? 0) === 0) {
    return c.json({ error: 'Conflict or not found', message: 'Version mismatch or shipment not found' }, 409);
  }

  return c.json({ message: 'Shipment updated', id: shipmentId });
});

/** DELETE /shipments/:id — soft delete */
shipmentRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const shipmentId = c.req.param('id');

  const result = await c.env.DB.prepare(
    `UPDATE shipments SET is_deleted = 1, deleted_by = ?, deleted_at = datetime('now'), updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(userId, shipmentId, tenantId).run();

  if ((result.meta.changes ?? 0) === 0) {
    return c.json({ error: 'Not Found' }, 404);
  }

  return c.json({ message: 'Shipment deleted', id: shipmentId });
});
