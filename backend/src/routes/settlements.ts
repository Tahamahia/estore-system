import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const settlementRoutes = new Hono<AppEnv>();

/**
 * Landed USD cost of one item row (per-unit cost — the purchaser's cost_usd
 * when set, else the foreign unit price — plus its weight-based shipping,
 * times quantity). Shared by order costing and write-offs so both use the
 * same rule.
 */
const ITEM_COST_USD_SQL = `
  (CASE WHEN COALESCE(oi.cost_usd,0) > 0 THEN oi.cost_usd ELSE COALESCE(oi.unit_price_foreign,0) END
   + COALESCE(oi.weight,0) * COALESCE(oi.shipping_rate_per_kg,0))
  * COALESCE(oi.quantity,1)`;

/**
 * Per-order money figures for settled orders, using the order-total-first
 * rule (orders.total_* when set, else the live — non-cancelled — items sum).
 *
 *   sale_lyd    — what the order was priced at.
 *   actual_lyd  — money actually received: deposit + cash_collected once
 *                 cash tracking recorded a collection, else the sale (legacy
 *                 orders delivered before cash tracking existed).
 *   is_forfeit  — a cancelled order linked to the settlement only for its
 *                 forfeited deposit: revenue = deposit, cost 0 (its lost or
 *                 returned item cost is handled by write-offs).
 */
const SETTLED_ORDERS_CTE = `
  order_item_sums AS (
    SELECT
      oi.order_id,
      SUM(CASE WHEN oi.status != 'cancelled' THEN COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1) ELSE 0 END) AS item_lyd,
      SUM(CASE WHEN oi.status != 'cancelled' THEN ${ITEM_COST_USD_SQL} ELSE 0 END) AS item_usd,
      COUNT(CASE WHEN oi.status != 'cancelled' THEN 1 END) AS live_item_count
    FROM order_items oi WHERE oi.tenant_id = ? AND oi.is_deleted = 0
    GROUP BY oi.order_id
  ),
  settled_orders AS (
    SELECT
      o.id, o.settlement_id, o.status, o.created_at, o.deposit_status,
      c.full_name AS customer_name, c.phone AS customer_phone,
      CASE WHEN o.status = 'cancelled' THEN 1 ELSE 0 END AS is_forfeit,
      COALESCE(o.total_sale_price_lyd, ois.item_lyd, 0) AS sale_lyd,
      COALESCE(o.total_cost_usd, ois.item_usd, 0) AS cost_usd,
      COALESCE(o.deposit_amount, 0) AS deposit_amount,
      COALESCE(o.cash_collected, 0) AS cash_collected,
      o.cash_collected_at,
      COALESCE(ois.live_item_count, 0) AS item_count
    FROM orders o
    LEFT JOIN order_item_sums ois ON ois.order_id = o.id
    LEFT JOIN customers c ON c.id = o.customer_id
    WHERE o.tenant_id = ? AND o.settlement_id IS NOT NULL AND o.is_deleted = 0
  ),
  settled_order_money AS (
    SELECT so.*,
      CASE
        WHEN is_forfeit = 1 THEN deposit_amount
        WHEN cash_collected_at IS NOT NULL THEN deposit_amount + cash_collected
        ELSE sale_lyd
      END AS actual_lyd,
      CASE WHEN is_forfeit = 1 THEN deposit_amount ELSE sale_lyd END AS booked_sale_lyd,
      CASE WHEN is_forfeit = 1 THEN 0 ELSE cost_usd END AS booked_cost_usd,
      CASE WHEN is_forfeit = 1 THEN 0
           ELSE MAX(sale_lyd - deposit_amount - cash_collected, 0) END AS cash_shortfall
    FROM settled_orders so
  )`;

type Financials = {
  total_lyd_collected: number;
  total_sale_lyd: number;
  door_discount_lyd: number;
  forfeited_deposits_lyd: number;
  total_usd_cost: number;
  order_count: number;
  forfeited_order_count: number;
  item_count: number;
  cash_shortfall: number;
  write_off_item_count: number;
  write_off_lost_usd: number;
  write_off_unsold_usd: number;
  total_write_off_usd: number;
  net_profit_usd: number;
};

/**
 * Aggregated financials per settlement (all of the tenant's, or one).
 * net_profit_usd = actual revenue / exchange_rate − cost − write-offs.
 */
async function loadFinancials(
  db: D1Database,
  tenantId: string,
  settlementId?: string,
): Promise<Map<string, Financials>> {
  const onlyOne = settlementId ? ' AND s.id = ?' : '';
  const args = settlementId ? [settlementId] : [];

  const [settlements, orderRows, writeOffRows] = await db.batch([
    db.prepare(
      `SELECT s.id, s.exchange_rate FROM settlements s WHERE s.tenant_id = ?${onlyOne}`
    ).bind(tenantId, ...args),
    db.prepare(
      `WITH ${SETTLED_ORDERS_CTE}
       SELECT
         settlement_id,
         SUM(actual_lyd)                                AS total_lyd_collected,
         SUM(booked_sale_lyd)                           AS total_sale_lyd,
         SUM(CASE WHEN is_forfeit = 1 THEN deposit_amount ELSE 0 END) AS forfeited_deposits_lyd,
         SUM(booked_cost_usd)                           AS total_usd_cost,
         SUM(1 - is_forfeit)                            AS order_count,
         SUM(is_forfeit)                                AS forfeited_order_count,
         SUM(CASE WHEN is_forfeit = 1 THEN 0 ELSE item_count END) AS item_count,
         SUM(cash_shortfall)                            AS cash_shortfall
       FROM settled_order_money
       ${settlementId ? 'WHERE settlement_id = ?' : ''}
       GROUP BY settlement_id`
    ).bind(tenantId, tenantId, ...args),
    db.prepare(
      `SELECT
         oi.written_off_settlement_id AS settlement_id,
         COUNT(*) AS write_off_item_count,
         COALESCE(SUM(CASE WHEN oi.lost_at IS NOT NULL THEN ${ITEM_COST_USD_SQL} ELSE 0 END), 0) AS write_off_lost_usd,
         COALESCE(SUM(CASE WHEN oi.lost_at IS NULL     THEN ${ITEM_COST_USD_SQL} ELSE 0 END), 0) AS write_off_unsold_usd
       FROM order_items oi
       WHERE oi.tenant_id = ? AND oi.written_off_settlement_id IS NOT NULL AND oi.is_deleted = 0
         ${settlementId ? 'AND oi.written_off_settlement_id = ?' : ''}
       GROUP BY oi.written_off_settlement_id`
    ).bind(tenantId, ...args),
  ]);

  const byId = <T>(rows: unknown[]) => {
    const m = new Map<string, T>();
    for (const r of rows as Record<string, unknown>[]) m.set(r.settlement_id as string, r as T);
    return m;
  };
  const orderMap = byId<Record<string, number>>(orderRows.results);
  const writeOffMap = byId<Record<string, number>>(writeOffRows.results);

  const out = new Map<string, Financials>();
  for (const s of settlements.results as { id: string; exchange_rate: number }[]) {
    const o = orderMap.get(s.id) ?? {};
    const w = writeOffMap.get(s.id) ?? {};
    const n = (v: unknown) => Number(v ?? 0);
    const collected = n(o.total_lyd_collected);
    const sale = n(o.total_sale_lyd);
    const cost = n(o.total_usd_cost);
    const lost = n(w.write_off_lost_usd);
    const unsold = n(w.write_off_unsold_usd);
    const rate = n(s.exchange_rate);
    out.set(s.id, {
      total_lyd_collected: collected,
      total_sale_lyd: sale,
      door_discount_lyd: sale - collected,
      forfeited_deposits_lyd: n(o.forfeited_deposits_lyd),
      total_usd_cost: cost,
      order_count: n(o.order_count),
      forfeited_order_count: n(o.forfeited_order_count),
      item_count: n(o.item_count),
      cash_shortfall: n(o.cash_shortfall),
      write_off_item_count: n(w.write_off_item_count),
      write_off_lost_usd: lost,
      write_off_unsold_usd: unsold,
      total_write_off_usd: lost + unsold,
      net_profit_usd: (rate > 0 ? collected / rate : 0) - cost - lost - unsold,
    });
  }
  return out;
}

/**
 * POST /settlements
 * Body: { name, exchange_rate, order_ids, write_off?: boolean, forfeited_order_ids?: string[] }
 *
 * One atomic batch:
 *   - links the delivered, unsettled order_ids;
 *   - links forfeited_order_ids (cancelled, deposit_status = 'forfeited',
 *     unsettled) — their deposit is revenue, their cost 0;
 *   - ALWAYS writes off lost items (lost_at set, not yet written off);
 *   - writes off unsold in-stock items only when write_off is true.
 */
settlementRoutes.post('/', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    name: string;
    exchange_rate: number;
    order_ids?: string[];
    write_off?: boolean;
    forfeited_order_ids?: string[];
  }>();

  const orderIds = [...new Set(body.order_ids ?? [])];
  const forfeitedIds = [...new Set(body.forfeited_order_ids ?? [])];

  if (!body.name?.trim() || !body.exchange_rate || (orderIds.length === 0 && forfeitedIds.length === 0)) {
    return c.json({ error: 'Bad Request', message: 'name, exchange_rate, and order_ids (or forfeited_order_ids) are required' }, 400);
  }
  if (body.exchange_rate <= 0) {
    return c.json({ error: 'Bad Request', message: 'exchange_rate must be positive' }, 400);
  }

  const ELIGIBLE_ORDER = `status = 'delivered' AND settlement_id IS NULL`;
  const ELIGIBLE_FORFEIT = `status = 'cancelled' AND deposit_status = 'forfeited'
                            AND COALESCE(deposit_amount, 0) > 0 AND settlement_id IS NULL`;

  const [eligibleOrders, eligibleForfeits] = await c.env.DB.batch([
    c.env.DB.prepare(
      `SELECT id FROM orders WHERE id IN (SELECT value FROM json_each(?))
       AND tenant_id = ? AND is_deleted = 0 AND ${ELIGIBLE_ORDER}`
    ).bind(JSON.stringify(orderIds), tenantId),
    c.env.DB.prepare(
      `SELECT id FROM orders WHERE id IN (SELECT value FROM json_each(?))
       AND tenant_id = ? AND is_deleted = 0 AND ${ELIGIBLE_FORFEIT}`
    ).bind(JSON.stringify(forfeitedIds), tenantId),
  ]);

  const okOrders = new Set((eligibleOrders.results as { id: string }[]).map((r) => r.id));
  const okForfeits = new Set((eligibleForfeits.results as { id: string }[]).map((r) => r.id));
  const invalidOrderIds = orderIds.filter((x) => !okOrders.has(x));
  const invalidForfeitIds = forfeitedIds.filter((x) => !okForfeits.has(x));

  if (invalidOrderIds.length > 0 || invalidForfeitIds.length > 0) {
    return c.json({
      error: 'validation_failed',
      message: 'بعض الطلبيات غير مؤهلة للتسوية',
      invalid_order_ids: invalidOrderIds,
      invalid_forfeited_order_ids: invalidForfeitIds,
    }, 400);
  }

  const id = crypto.randomUUID();

  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `INSERT INTO settlements (id, tenant_id, name, exchange_rate) VALUES (?, ?, ?, ?)`
    ).bind(id, tenantId, body.name.trim(), body.exchange_rate),
    c.env.DB.prepare(
      `UPDATE orders SET settlement_id = ?, updated_at = datetime('now')
       WHERE id IN (SELECT value FROM json_each(?)) AND tenant_id = ? AND is_deleted = 0 AND ${ELIGIBLE_ORDER}`
    ).bind(id, JSON.stringify(orderIds), tenantId),
    c.env.DB.prepare(
      `UPDATE orders SET settlement_id = ?, updated_at = datetime('now')
       WHERE id IN (SELECT value FROM json_each(?)) AND tenant_id = ? AND is_deleted = 0 AND ${ELIGIBLE_FORFEIT}`
    ).bind(id, JSON.stringify(forfeitedIds), tenantId),
    // Lost items are always expensed — not gated by the write_off checkbox.
    c.env.DB.prepare(
      `UPDATE order_items SET written_off_settlement_id = ?, updated_at = datetime('now'), version = version + 1
       WHERE tenant_id = ? AND lost_at IS NOT NULL AND written_off_settlement_id IS NULL AND is_deleted = 0`
    ).bind(id, tenantId),
  ];

  if (body.write_off === true) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET written_off_settlement_id = ?, updated_at = datetime('now'), version = version + 1
         WHERE tenant_id = ? AND order_id IS NULL AND status = 'in_stock'
           AND written_off_settlement_id IS NULL AND is_deleted = 0`
      ).bind(id, tenantId)
    );
  }

  await c.env.DB.batch(stmts);

  const fin = (await loadFinancials(c.env.DB, tenantId, id)).get(id)!;

  return c.json({
    id,
    name: body.name.trim(),
    exchange_rate: body.exchange_rate,
    ...fin,
    write_off_count: fin.write_off_item_count,
    write_off_total_usd: fin.total_write_off_usd,
  }, 201);
});

/**
 * GET /settlements
 * Returns all settlements with aggregated financials and write-off totals.
 */
settlementRoutes.get('/', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');

  const settlements = await c.env.DB.prepare(
    `SELECT id, name, exchange_rate, created_at FROM settlements
     WHERE tenant_id = ?
     ORDER BY created_at DESC`
  ).bind(tenantId).all();

  if (!settlements.results.length) {
    return c.json({ data: [] });
  }

  const fin = await loadFinancials(c.env.DB, tenantId);
  const data = settlements.results.map((s) => ({ ...s, ...fin.get(s.id as string) }));

  return c.json({ data });
});

// GET /settlements/:id — detail with linked orders (incl. forfeited-deposit orders)
settlementRoutes.get('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const id = c.req.param('id')!;

  const settlement = await c.env.DB.prepare(
    `SELECT * FROM settlements WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!settlement) return c.json({ error: 'Not Found' }, 404);

  // Per-order cash_shortfall = max(sale − deposit − cash_collected, 0); an
  // overpayment does not offset another order's shortfall. Forfeited-deposit
  // orders carry no shortfall.
  const orders = await c.env.DB.prepare(
    `WITH ${SETTLED_ORDERS_CTE}
     SELECT id, status, created_at, deposit_amount, deposit_status, cash_collected,
            cash_collected_at, customer_name, customer_phone, item_count,
            is_forfeit, sale_lyd AS total_lyd, actual_lyd,
            booked_sale_lyd - actual_lyd AS door_discount_lyd,
            cash_shortfall
     FROM settled_order_money
     WHERE settlement_id = ?
     ORDER BY created_at ASC`
  ).bind(tenantId, tenantId, id).all();

  const fin = (await loadFinancials(c.env.DB, tenantId, id)).get(id);

  return c.json({ ...settlement, ...fin, orders: orders.results });
});

// PATCH /settlements/:id — edit name and exchange_rate only
settlementRoutes.patch('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const id = c.req.param('id');
  const body = await c.req.json();

  const existing = await c.env.DB.prepare(
    `SELECT id FROM settlements WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];

  if (body.name !== undefined) {
    setClauses.push('name = ?');
    values.push(body.name);
  }
  if (body.exchange_rate !== undefined) {
    if (typeof body.exchange_rate !== 'number' || body.exchange_rate <= 0) {
      return c.json({ error: 'Bad Request', message: 'exchange_rate must be a positive number' }, 400);
    }
    setClauses.push('exchange_rate = ?');
    values.push(body.exchange_rate);
  }

  if (values.length === 0) {
    return c.json({ error: 'Bad Request', message: 'No valid fields provided. Allowed: name, exchange_rate' }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE settlements SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
  ).bind(...values, id, tenantId).run();

  return c.json({ message: 'Updated', id });
});

// DELETE /settlements/:id — unlink orders, undo write-offs, then delete
settlementRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const id = c.req.param('id');

  const existing = await c.env.DB.prepare(
    `SELECT id FROM settlements WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE order_items
      SET written_off_settlement_id = NULL, updated_at = datetime('now'), version = version + 1
      WHERE written_off_settlement_id = ? AND tenant_id = ?
    `).bind(id, tenantId),
    c.env.DB.prepare(`
      UPDATE orders SET settlement_id = NULL, updated_at = datetime('now')
      WHERE settlement_id = ? AND tenant_id = ?
    `).bind(id, tenantId),
    c.env.DB.prepare(
      `DELETE FROM settlements WHERE id = ? AND tenant_id = ?`
    ).bind(id, tenantId),
  ]);

  return c.json({ message: 'تم حذف التسوية', id });
});
