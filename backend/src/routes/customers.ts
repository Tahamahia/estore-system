import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const customerRoutes = new Hono<AppEnv>();

customerRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page = parseInt(c.req.query('page') || '1');
  const limit = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;
  const search = c.req.query('search');

  let query = `SELECT * FROM customers WHERE tenant_id = ? AND is_deleted = 0`;
  const bindings: any[] = [tenantId];

  if (search) {
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

customerRoutes.post('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  if (!body.id || !body.full_name) return c.json({ error: 'id and full_name required' }, 400);
  await c.env.DB.prepare(
    `INSERT INTO customers (id, tenant_id, full_name, phone, address, city, notes, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
  ).bind(body.id, tenantId, body.full_name, body.phone || null, body.address || null, body.city || null, body.notes || null).run();
  return c.json({ message: 'Customer created', id: body.id }, 201);
});
