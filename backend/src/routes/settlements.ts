import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const settlementRoutes = new Hono<AppEnv>();

const D1_BATCH_LIMIT = 99;

function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

/**
 * POST /settlements
 * Body: { name: string, exchange_rate: number, order_ids: string[] }
 * Creates a settlement, links orders, and writes off all unsold in-stock items.
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

  // Execute in chunks to stay within D1 batch limit
  for (const chunk of chunkArray(stmts, D1_BATCH_LIMIT)) {
    await c.env.DB.batch(chunk);
  }

  // Write off all unsold in-stock items that haven't been written off yet
  const unsoldItems = await c.env.DB.prepare(`
    SELECT id, cost_usd, unit_price_foreign, weight, shipping_rate_per_kg, quantity
    FROM order_items
    WHERE tenant_id = ? AND order_id IS NULL AND status = 'in_stock'
      AND written_off_settlement_id IS NULL AND is_deleted = 0
  `).bind(tenantId).all();

  let writeOffCount = 0;
  let writeOffTotalUsd = 0;

  if (unsoldItems.results.length > 0) {
    const writeOffStmts: D1PreparedStatement[] = unsoldItems.results.map((item: any) => {
      const costUsd = Number(item.cost_usd ?? 0);
      const unitForeign = Number(item.unit_price_foreign ?? 0);
      const weight = Number(item.weight ?? 0);
      const rate = Number(item.shipping_rate_per_kg ?? 0);
      const qty = Number(item.quantity ?? 1);
      const perUnit = costUsd > 0 ? costUsd : unitForeign;
      writeOffTotalUsd += (perUnit + weight * rate) * qty;
      writeOffCount++;
      return c.env.DB.prepare(
        `UPDATE order_items SET written_off_settlement_id = ?, updated_at = datetime('now'), version = version + 1
         WHERE id = ? AND tenant_id = ?`
      ).bind(id, item.id, tenantId);
    });

    for (const chunk of chunkArray(writeOffStmts, D1_BATCH_LIMIT)) {
      await c.env.DB.batch(chunk);
    }
  }

  return c.json({
    id,
    name: body.name,
    exchange_rate: body.exchange_rate,
    order_count: body.order_ids.length,
    write_off_count: writeOffCount,
    write_off_total_usd: writeOffTotalUsd,
  }, 201);
});

/**
 * GET /settlements
 * Returns all settlements for the tenant with aggregated financials.
 *
 * total_lyd_collected: sum of (unit_price_local * quantity) for all non-cancelled items
 * total_usd_cost: sum of live cost formula per non-cancelled item
 * total_write_off_usd: sum of cost for items written off against this settlement
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

  // Aggregate order financials for all settlements in one query
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
              THEN (CASE WHEN COALESCE(oi.cost_usd, 0) > 0 THEN oi.cost_usd ELSE COALESCE(oi.unit_price_foreign, 0) END
                    + COALESCE(oi.weight, 0) * COALESCE(oi.shipping_rate_per_kg, 0))
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

  // Aggregate write-off totals per settlement
  const writeOffs = await c.env.DB.prepare(
    `SELECT
       written_off_settlement_id AS settlement_id,
       COUNT(*) AS write_off_item_count,
       COALESCE(SUM(
         (CASE WHEN COALESCE(cost_usd, 0) > 0 THEN cost_usd ELSE COALESCE(unit_price_foreign, 0) END
          + COALESCE(weight, 0) * COALESCE(shipping_rate_per_kg, 0))
         * COALESCE(quantity, 1)
       ), 0) AS total_write_off_usd
     FROM order_items
     WHERE tenant_id = ? AND written_off_settlement_id IS NOT NULL AND is_deleted = 0
     GROUP BY written_off_settlement_id`
  ).bind(tenantId).all();

  // Index by settlement_id for O(1) lookup
  const finMap = new Map<string, Record<string, unknown>>();
  for (const row of financials.results) {
    finMap.set(row.settlement_id as string, row as Record<string, unknown>);
  }

  const writeOffMap = new Map<string, Record<string, unknown>>();
  for (const row of writeOffs.results) {
    writeOffMap.set(row.settlement_id as string, row as Record<string, unknown>);
  }

  const data = settlements.results.map((s) => {
    const fin = finMap.get(s.id as string) ?? {
      total_lyd_collected: 0,
      total_usd_cost: 0,
      order_count: 0,
      item_count: 0,
    };
    const wo = writeOffMap.get(s.id as string) ?? {
      write_off_item_count: 0,
      total_write_off_usd: 0,
    };
    return { ...s, ...fin, ...wo };
  });

  return c.json({ data });
});
