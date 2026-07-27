import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const settlementRoutes = new Hono<AppEnv>();

/**
 * POST /settlements
 * Body: { name: string, exchange_rate: number, order_ids: string[] }
 * Creates a settlement and links the given orders to it.
 */
settlementRoutes.post('/', async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    name: string;
    exchange_rate: number;
    order_ids: string[];
  }>();

  if (!body.name || !body.exchange_rate || !body.order_ids?.length) {
    return c.json({ error: 'Bad Request', message: 'name, exchange_rate, and order_ids are required' }, 400);
  }
  if (body.exchange_rate <= 0) {
    return c.json({ error: 'Bad Request', message: 'exchange_rate must be positive' }, 400);
  }

  const id = crypto.randomUUID();

  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `INSERT INTO settlements (id, tenant_id, name, exchange_rate) VALUES (?, ?, ?, ?)`
    ).bind(id, tenantId, body.name.trim(), body.exchange_rate),
  ];

  // Verify and link each order — only update orders that belong to this tenant
  for (const orderId of body.order_ids) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE orders SET settlement_id = ? WHERE id = ? AND tenant_id = ?`
      ).bind(id, orderId, tenantId)
    );
  }

  await c.env.DB.batch(stmts);

  return c.json({ id, name: body.name, exchange_rate: body.exchange_rate, order_count: body.order_ids.length }, 201);
});

/**
 * GET /settlements
 * Returns all settlements for the tenant with aggregated financials.
 *
 * total_lyd_collected: sum of (unit_price_local * quantity) for all non-cancelled items
 * total_usd_cost: sum of (unit_price_foreign + weight * shipping_rate_per_kg) * quantity
 */
settlementRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id');

  const settlements = await c.env.DB.prepare(
    `SELECT id, name, exchange_rate, created_at FROM settlements
     WHERE tenant_id = ?
     ORDER BY created_at DESC`
  ).bind(tenantId).all();

  if (!settlements.results.length) {
    return c.json({ data: [] });
  }

  // Aggregate financials for all settlements in one query
  const financials = await c.env.DB.prepare(
    `SELECT
       o.settlement_id,
       COALESCE(SUM(
         CASE WHEN oi.status != 'cancelled'
              THEN COALESCE(oi.unit_price_local, 0) * COALESCE(oi.quantity, 1)
              ELSE 0 END
       ), 0) AS total_lyd_collected,
       COALESCE(SUM(
         CASE WHEN oi.status != 'cancelled'
              THEN (COALESCE(oi.unit_price_foreign, 0) +
                    COALESCE(oi.weight, 0) * COALESCE(oi.shipping_rate_per_kg, 0))
                   * COALESCE(oi.quantity, 1)
              ELSE 0 END
       ), 0) AS total_usd_cost,
       COUNT(DISTINCT o.id) AS order_count,
       COUNT(CASE WHEN oi.status != 'cancelled' THEN 1 END) AS item_count
     FROM orders o
     JOIN order_items oi ON oi.order_id = o.id
     WHERE o.tenant_id = ? AND o.settlement_id IS NOT NULL
     GROUP BY o.settlement_id`
  ).bind(tenantId).all();

  // Index financials by settlement_id for O(1) lookup
  const finMap = new Map<string, Record<string, unknown>>();
  for (const row of financials.results) {
    finMap.set(row.settlement_id as string, row as Record<string, unknown>);
  }

  const data = settlements.results.map((s) => {
    const fin = finMap.get(s.id as string) ?? {
      total_lyd_collected: 0,
      total_usd_cost: 0,
      order_count: 0,
      item_count: 0,
    };
    return { ...s, ...fin };
  });

  return c.json({ data });
});
