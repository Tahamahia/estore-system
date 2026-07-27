import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const customerRoutes = new Hono<AppEnv>();

/**
 * Normalize a phone number: strip spaces, dashes, parens. Keep + and digits only.
 */
function normalizePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const cleaned = phone.replace(/[\s\-\(\)\.]/g, '');
  return cleaned.length >= 5 ? cleaned : null;
}

/**
 * GET /customers — List/search customers
 * Supports ?search= for name/phone fuzzy matching and ?phone= for exact phone lookup
 */
customerRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;
  const search = c.req.query('search');
  const phone = c.req.query('phone'); // Exact phone lookup for debounce

  let query = `SELECT * FROM customers WHERE tenant_id = ? AND is_deleted = 0`;
  const bindings: any[] = [tenantId];

  if (phone) {
    // Exact phone match for phone-first identity
    const normalized = normalizePhone(phone);
    if (normalized) {
      query += ` AND phone = ?`;
      bindings.push(normalized);
    }
  } else if (search) {
    query += ` AND (full_name LIKE ? OR phone LIKE ?)`;
    bindings.push(`%${search}%`, `%${search}%`);
  }

  query += ` ORDER BY full_name ASC LIMIT ? OFFSET ?`;
  bindings.push(limit, offset);

  const results = await c.env.DB.prepare(query).bind(...bindings).all();
  return c.json({ data: results.results, page, limit });
});

customerRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const customer = await c.env.DB.prepare(
    `SELECT * FROM customers WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(c.req.param('id'), tenantId).first();
  if (!customer) return c.json({ error: 'Not Found' }, 404);
  const wallet = await c.env.DB.prepare(
    `SELECT * FROM customer_wallets WHERE customer_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(c.req.param('id'), tenantId).first();
  return c.json({ ...customer, wallet_balance: (wallet as any)?.balance || 0 });
});

/**
 * POST /customers — Silent Upsert
 * If phone already exists for tenant → returns existing customer (200, not 409)
 * If phone is new → creates customer (201)
 * This is the "Phone-First Identity" pattern.
 */
customerRoutes.post('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  if (!body.id || !body.full_name) return c.json({ error: 'id and full_name required' }, 400);

  const normalizedPhone = normalizePhone(body.phone);

  // Silent upsert: check if phone already exists
  if (normalizedPhone) {
    const existing = await c.env.DB.prepare(
      `SELECT id, full_name, phone FROM customers WHERE phone = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(normalizedPhone, tenantId).first();

    if (existing) {
      // Phone exists → return existing customer silently (no error!)
      return c.json({
        message: 'Existing customer matched by phone',
        id: existing.id,
        full_name: existing.full_name,
        phone: existing.phone,
        is_existing: true,
      }, 200);
    }
  }

  // New customer — insert
  await c.env.DB.prepare(
    `INSERT INTO customers (id, tenant_id, full_name, phone, phone2, address, city, area, street, location_url, notes, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
  ).bind(
    body.id, tenantId, body.full_name, normalizedPhone,
    normalizePhone(body.phone2),
    body.address || null, body.city || null,
    body.area || null, body.street || null, body.location_url || null,
    body.notes || null
  ).run();

  return c.json({ message: 'Customer created', id: body.id, is_existing: false }, 201);
});

/**
 * PATCH /customers/:id — Update customer fields (OCC with version column)
 */
customerRoutes.patch('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const customerId = c.req.param('id');
  const body = await c.req.json();
  const { version, ...updates } = body;

  if (!version) {
    return c.json({ error: 'Bad Request', message: 'version field required for OCC' }, 400);
  }

  // Build dynamic SET clause from allowed fields
  const setClauses: string[] = [];
  const values: any[] = [];
  const allowedFields = ['full_name', 'phone', 'phone2', 'address', 'city', 'area', 'street', 'location_url', 'notes'];

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      if (field === 'phone' || field === 'phone2') {
        setClauses.push(`${field} = ?`);
        values.push(normalizePhone(updates[field]));
      } else {
        setClauses.push(`${field} = ?`);
        values.push(updates[field]);
      }
    }
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'Bad Request', message: 'No valid fields to update' }, 400);
  }

  setClauses.push(`version = version + 1`);
  setClauses.push(`updated_at = datetime('now')`);

  const result = await c.env.DB.prepare(
    `UPDATE customers SET ${setClauses.join(', ')}
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(...values, customerId, tenantId, version).run();

  if (result.meta.changes === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Customer was modified by another request (version mismatch) or not found'
    }, 409);
  }

  return c.json({ message: 'Customer updated', id: customerId });
});

/**
 * DELETE /customers/:id — Soft delete a customer
 * Restricted to super_admin and store_manager roles.
 */
customerRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const customerId = c.req.param('id');

  const result = await c.env.DB.prepare(
    `UPDATE customers SET is_deleted = 1, deleted_by = ?, deleted_at = datetime('now'), updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(userId, customerId, tenantId).run();

  if (result.meta.changes === 0) {
    return c.json({ error: 'Not Found', message: 'Customer not found' }, 404);
  }

  return c.json({ message: 'Customer soft-deleted', id: customerId });
});
