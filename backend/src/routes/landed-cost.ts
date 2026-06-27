import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const landedCostRoutes = new Hono<AppEnv>();

/**
 * POST /landed-cost/calculate/:master_shipment_id
 * 
 * Distributes master shipment costs (customs + freight + other) across
 * individual items pro-rata based on MAX(Actual_Weight, Volumetric_Weight).
 * 
 * ALL math uses INTEGER CENTS to prevent floating-point rounding errors.
 * 
 * Formula per item:
 *   item_share = total_cost_cents * item_weight / total_weight
 *   net_profit_cents = sell_price_cents - purchase_price_cents - landed_cost_cents
 */
landedCostRoutes.post(
  '/calculate/:master_shipment_id',
  requireRole('super_admin', 'store_manager'),
  async (c) => {
    const tenantId = c.get('tenant_id');
    const masterId = c.req.param('master_shipment_id');

    // 1. Get master shipment costs
    const master = await c.env.DB.prepare(
      `SELECT id, customs_cost, freight_cost, other_costs, version
       FROM master_shipments
       WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(masterId, tenantId).first();

    if (!master) {
      return c.json({ error: 'Not Found', message: 'Master shipment not found' }, 404);
    }

    // Convert costs to integer cents
    const customsCents = Math.round(((master.customs_cost as number) || 0) * 100);
    const freightCents = Math.round(((master.freight_cost as number) || 0) * 100);
    const otherCents = Math.round(((master.other_costs as number) || 0) * 100);
    const totalCostCents = customsCents + freightCents + otherCents;

    if (totalCostCents <= 0) {
      return c.json({ error: 'Bad Request', message: 'Master shipment has no costs to distribute' }, 400);
    }

    // 2. Get all items in shipments belonging to this master
    const items = await c.env.DB.prepare(
      `SELECT oi.id, oi.actual_weight, oi.volumetric_weight,
              oi.unit_price_local, oi.purchase_price
       FROM order_items oi
       JOIN shipments s ON oi.shipment_id = s.id
       WHERE s.master_shipment_id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(masterId, tenantId).all();

    if (!items.results?.length) {
      return c.json({ error: 'Bad Request', message: 'No items found in this master shipment' }, 400);
    }

    // 3. Calculate effective weight per item: MAX(actual, volumetric)
    // Default weight = 0.1 kg if both are null/0 (prevents divide-by-zero)
    const DEFAULT_WEIGHT_KG = 0.1;
    const itemWeights: Array<{ id: string; effectiveWeight: number }> = [];
    let totalWeight = 0;

    for (const item of items.results) {
      const actual = (item.actual_weight as number) || 0;
      const volumetric = (item.volumetric_weight as number) || 0;
      let effectiveWeight = Math.max(actual, volumetric);

      // Guard: if both weights are 0/null, use default
      if (effectiveWeight <= 0) {
        effectiveWeight = DEFAULT_WEIGHT_KG;
      }

      itemWeights.push({ id: item.id as string, effectiveWeight });
      totalWeight += effectiveWeight;
    }

    // 4. CRITICAL: Guard against divide-by-zero
    if (totalWeight <= 0) {
      return c.json({
        error: 'Calculation Error',
        message: 'Total weight is zero — cannot distribute costs. Assign weights to items first.',
      }, 400);
    }

    // 5. Distribute costs pro-rata and compute net profit
    const stmts: D1PreparedStatement[] = [];
    const breakdown: Array<{
      item_id: string;
      effective_weight_kg: number;
      weight_share_pct: number;
      landed_cost_cents: number;
      net_profit_cents: number | null;
    }> = [];

    // Track distributed cents to handle rounding remainder
    let distributedCents = 0;

    for (let i = 0; i < itemWeights.length; i++) {
      const iw = itemWeights[i];
      const item = items.results[i];

      let landedCostCents: number;
      if (i === itemWeights.length - 1) {
        // Last item gets the remainder to ensure sum == totalCostCents exactly
        landedCostCents = totalCostCents - distributedCents;
      } else {
        landedCostCents = Math.round(totalCostCents * iw.effectiveWeight / totalWeight);
      }
      distributedCents += landedCostCents;

      const weightSharePct = Math.round((iw.effectiveWeight / totalWeight) * 10000) / 100;

      // Net profit: sell_price - purchase_price - landed_cost (all in cents)
      const sellPriceCents = Math.round(((item.unit_price_local as number) || 0) * 100);
      const purchasePriceCents = Math.round(((item.purchase_price as number) || 0) * 100);
      const netProfitCents = sellPriceCents > 0
        ? sellPriceCents - purchasePriceCents - landedCostCents
        : null;  // null if sell price not set

      stmts.push(
        c.env.DB.prepare(
          `UPDATE order_items SET
             landed_cost = ?,
             net_profit = ?,
             updated_at = datetime('now')
           WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
        ).bind(
          landedCostCents / 100,
          netProfitCents !== null ? netProfitCents / 100 : null,
          iw.id,
          tenantId
        )
      );

      breakdown.push({
        item_id: iw.id,
        effective_weight_kg: iw.effectiveWeight,
        weight_share_pct: weightSharePct,
        landed_cost_cents: landedCostCents,
        net_profit_cents: netProfitCents,
      });
    }

    // Update master shipment total_weight
    stmts.push(
      c.env.DB.prepare(
        `UPDATE master_shipments SET
           total_weight = ?,
           status = 'processed',
           version = version + 1,
           updated_at = datetime('now')
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(totalWeight, masterId, tenantId)
    );

    await c.env.DB.batch(stmts);

    // Summary
    const totalDistributed = breakdown.reduce((sum, b) => sum + b.landed_cost_cents, 0);
    const lossItems = breakdown.filter(b => b.net_profit_cents !== null && b.net_profit_cents < 0);

    return c.json({
      message: 'Landed cost calculated and distributed',
      master_shipment_id: masterId,
      total_cost_cents: totalCostCents,
      total_distributed_cents: totalDistributed,
      rounding_diff_cents: totalCostCents - totalDistributed,  // Should always be 0
      total_weight_kg: totalWeight,
      items_count: breakdown.length,
      loss_items_count: lossItems.length,
      loss_warning: lossItems.length > 0
        ? `⚠️ ${lossItems.length} item(s) have negative net profit after landed cost.`
        : null,
      breakdown,
    });
  }
);

/**
 * GET /landed-cost/summary/:master_shipment_id — View cost distribution
 */
landedCostRoutes.get('/summary/:master_shipment_id', async (c) => {
  const tenantId = c.get('tenant_id');
  const masterId = c.req.param('master_shipment_id');

  const items = await c.env.DB.prepare(
    `SELECT oi.id, oi.product_name, oi.actual_weight, oi.volumetric_weight,
            oi.purchase_price, oi.unit_price_local, oi.landed_cost, oi.net_profit
     FROM order_items oi
     JOIN shipments s ON oi.shipment_id = s.id
     WHERE s.master_shipment_id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0
     ORDER BY oi.net_profit ASC`
  ).bind(masterId, tenantId).all();

  return c.json({
    master_shipment_id: masterId,
    items: items.results,
    total_items: items.results?.length || 0,
  });
});
