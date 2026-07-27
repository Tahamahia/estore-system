import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const settingsRoutes = new Hono<AppEnv>();

// ─── Shipping Sources CRUD ─────────────────────────────────

settingsRoutes.get('/sources', async (c) => {
  const result = await c.env.DB.prepare(
    `SELECT id, name, rate_per_kg FROM shipping_sources ORDER BY name ASC`
  ).all();
  return c.json({ data: result.results });
});

settingsRoutes.post('/sources', requireRole('super_admin', 'store_manager'), async (c) => {
  const body = await c.req.json<{ name: string; rate_per_kg: number }>();
  if (!body.name || body.rate_per_kg == null || body.rate_per_kg < 0) {
    return c.json({ error: 'Bad Request', message: 'name and non-negative rate_per_kg required' }, 400);
  }
  const result = await c.env.DB.prepare(
    `INSERT INTO shipping_sources (name, rate_per_kg) VALUES (?, ?) RETURNING id, name, rate_per_kg`
  ).bind(body.name.trim(), body.rate_per_kg).first();
  return c.json(result, 201);
});

settingsRoutes.put('/sources/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const id = Number(c.req.param('id'));
  const body = await c.req.json<{ name?: string; rate_per_kg?: number }>();
  const setClauses: string[] = [];
  const values: (string | number)[] = [];
  if (body.name !== undefined) { setClauses.push('name = ?'); values.push(body.name.trim()); }
  if (body.rate_per_kg !== undefined) { setClauses.push('rate_per_kg = ?'); values.push(body.rate_per_kg); }
  if (!setClauses.length) return c.json({ error: 'Bad Request', message: 'Nothing to update' }, 400);
  values.push(id);
  await c.env.DB.prepare(
    `UPDATE shipping_sources SET ${setClauses.join(', ')} WHERE id = ?`
  ).bind(...values).run();
  const updated = await c.env.DB.prepare(
    `SELECT id, name, rate_per_kg FROM shipping_sources WHERE id = ?`
  ).bind(id).first();
  if (!updated) return c.json({ error: 'Not Found' }, 404);
  return c.json(updated);
});

settingsRoutes.delete('/sources/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const id = Number(c.req.param('id'));
  await c.env.DB.prepare(`DELETE FROM shipping_sources WHERE id = ?`).bind(id).run();
  return c.json({ message: 'Deleted' });
});
