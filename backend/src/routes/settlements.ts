import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

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
 * Body: { name, exchange_rate, order_ids, write_off?: boolean }
 * Validates eligibility, creates settlement, links orders, optionally writes off in-stock items.
 */
settlementRoutes.post('/', async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    name: string;
    exchange_rate: number;
    order_ids: string[];
    write_off?: boolean;
  }>();

  if (!body.name || !body.exchange_rate || !body.order_ids?.length) {
    return c.json({ error: 'Bad Request', message: 'name, exchange_rate, and order_ids are required' }, 400);
  }
  if (body.exchange_rate <= 0) {
    return c.json({ error: 'Bad Request', message: 'exchange_rate must be positive' }, 400);
  }

  // Validate every order is delivered and not already settled
  const invalid = await c.env.DB.prepare(`
    SELECT id FROM orders
    WHERE id IN (SELECT value FROM json_each(?))
      AND tenant_id = ?
      AND (status != 'delivered' OR settlement_id IS NOT NULL)
  `).bind(JSON.stringify(body.order_ids), tenantId).all();

  if (invalid.results.length > 0) {
    const invalidIds = invalid.results.map((r) => (r as Record<string, unknown>).id as string);
    return c.json({
      error: 'validation_failed',
      message: 'بعض الطلبيات غير مؤهلة للتسوية',
      invalid_order_ids: invalidIds,
    }, 400);
  }

  const id = crypto.randomUUID();

  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `INSERT INTO settlements (id, tenant_id, name, exchange_rate) VALUES (?, ?, ?, ?)`
    ).bind(id, tenantId, body.name.trim(), body.exchange_rate),
  ];

  for (const orderId of body.order_ids) {
    stmts.push(
      c.env.DB.prepare(
        `UPDATE orders SET settlement_id = ? WHERE id = ? AND tenant_id = ?`
      ).bind(id, orderId, tenantId)
    );
  }

  for (const chunk of chunkArray(stmts, D1_BATCH_LIMIT)) {
    await c.env.DB.batch(chunk);
  }

  let writeOffCount = 0;
  let writeOffTotalUsd = 0;

  if (body.write_off === true) {
    const unsoldItems = await c.env.DB.prepare(`
      SELECT id, cost_usd, unit_price_foreign, weight, shipping_rate_per_kg, quantity
      FROM order_items
      WHERE tenant_id = ? AND order_id IS NULL AND status = 'in_stock'
        AND written_off_settlement_id IS NULL AND is_deleted = 0
    `).bind(tenantId).all();

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
 * Returns all settlements with aggregated financials and write-off totals.
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

  const financials = await c.env.DB.prepare(
    `WITH order_item_sums AS (
       SELECT
         oi.order_id,
         SUM(CASE WHEN oi.status != 'cancelled' THEN COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1) ELSE 0 END) AS item_lyd,
         SUM(CASE WHEN oi.status != 'cancelled' THEN
           (CASE WHEN COALESCE(oi.cost_usd,0) > 0 THEN oi.cost_usd ELSE COALESCE(oi.unit_price_foreign,0) END
            + COALESCE(oi.weight,0) * COALESCE(oi.shipping_rate_per_kg,0))
           * COALESCE(oi.quantity,1) ELSE 0 END) AS item_usd,
         COUNT(CASE WHEN oi.status != 'cancelled' THEN 1 END) AS live_item_count
       FROM order_items oi WHERE oi.tenant_id = ? AND oi.is_deleted = 0
       GROUP BY oi.order_id
     )
     SELECT
       o.settlement_id,
       COALESCE(SUM(COALESCE(o.total_sale_price_lyd, ois.item_lyd, 0)), 0) AS total_lyd_collected,
       COALESCE(SUM(COALESCE(o.total_cost_usd, ois.item_usd, 0)), 0) AS total_usd_cost,
       COUNT(DISTINCT o.id) AS order_count,
       COALESCE(SUM(ois.live_item_count), 0) AS item_count,
       COALESCE(SUM(
         CASE
           WHEN COALESCE(o.total_sale_price_lyd, ois.item_lyd, 0)
                - COALESCE(o.deposit_amount, 0)
                - COALESCE(o.cash_collected, 0) > 0
           THEN COALESCE(o.total_sale_price_lyd, ois.item_lyd, 0)
                - COALESCE(o.deposit_amount, 0)
                - COALESCE(o.cash_collected, 0)
           ELSE 0
         END
       ), 0) AS cash_shortfall
     FROM orders o
     LEFT JOIN order_item_sums ois ON ois.order_id = o.id
     WHERE o.tenant_id = ? AND o.settlement_id IS NOT NULL
     GROUP BY o.settlement_id`
  ).bind(tenantId, tenantId).all();

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

// GET /settlements/:id — detail with linked orders
settlementRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id');
  const id = c.req.param('id');

  const settlement = await c.env.DB.prepare(
    `SELECT * FROM settlements WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!settlement) return c.json({ error: 'Not Found' }, 404);

  const orders = await c.env.DB.prepare(`
    SELECT o.id, o.status, o.created_at,
           o.deposit_amount, o.cash_collected,
           c.full_name AS customer_name, c.phone AS customer_phone,
           COUNT(oi.id) AS item_count,
           COALESCE(
             o.total_sale_price_lyd,
             SUM(COALESCE(oi.unit_price_local,0) * COALESCE(oi.quantity,1)),
             0
           ) AS total_lyd
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id AND oi.is_deleted = 0 AND oi.status != 'cancelled'
    WHERE o.settlement_id = ? AND o.tenant_id = ? AND o.is_deleted = 0
    GROUP BY o.id ORDER BY o.created_at ASC
  `).bind(id, tenantId).all();

  // Compute per-order cash_shortfall and roll up to an aggregate for the
  // settlement. Shortfall = max(sale − deposit − cash_collected, 0). Any
  // overpayment is treated as zero shortfall (it does not offset another
  // order's shortfall). Both fields returned so the UI can render per-order
  // rows and the card total without recomputing.
  const ordersWithShortfall = (orders.results as Record<string, unknown>[]).map((o) => {
    const sale = Number(o.total_lyd ?? 0);
    const deposit = Number(o.deposit_amount ?? 0);
    const collected = Number(o.cash_collected ?? 0);
    const diff = sale - deposit - collected;
    const shortfall = diff > 0 ? diff : 0;
    return { ...o, cash_shortfall: shortfall };
  });
  const cashShortfall = ordersWithShortfall.reduce(
    (sum, o) => sum + Number(o.cash_shortfall ?? 0),
    0,
  );

  return c.json({ ...settlement, cash_shortfall: cashShortfall, orders: ordersWithShortfall });
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
