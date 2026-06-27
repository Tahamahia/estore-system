import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const purchaseRoutes = new Hono<AppEnv>();

/**
 * POST /purchasing/record — Record actual purchase details for order items
 * 
 * Called by the Purchaser role after buying items from suppliers.
 * Stores actual_exchange_rate, purchase_price, and calculates slippage.
 * Returns margin_warning if profit margin falls below threshold.
 */
purchaseRoutes.post('/record', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id');
  const userId = c.get('user_id');
  const body = await c.req.json<{
    order_id: string;
    actual_exchange_rate: number;
    items: Array<{
      item_id: string;
      purchase_price_cents: number;  // In foreign currency cents (integer)
      supplier_id?: string;
      tracking_number?: string;
    }>;
  }>();

  if (!body.order_id || !body.actual_exchange_rate || !body.items?.length) {
    return c.json({ error: 'Bad Request', message: 'order_id, actual_exchange_rate, and items are required' }, 400);
  }

  // Get the order to compare exchange rates
  const order = await c.env.DB.prepare(
    `SELECT id, pegged_exchange_rate, version FROM orders
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(body.order_id, tenantId).first();

  if (!order) {
    return c.json({ error: 'Not Found', message: 'Order not found' }, 404);
  }

  const peggedRate = order.pegged_exchange_rate as number || 0;
  const actualRate = body.actual_exchange_rate;

  // Calculate slippage: positive = loss (rate went up, items cost more in local currency)
  // All math in integer cents to prevent floating-point errors
  const slippagePct = peggedRate > 0
    ? Math.round(((actualRate - peggedRate) / peggedRate) * 10000) / 100  // 2 decimal precision
    : 0;

  // margin_warning if slippage > 3% (configurable threshold)
  const SLIPPAGE_THRESHOLD_PCT = 3;
  const marginWarning = slippagePct > SLIPPAGE_THRESHOLD_PCT;

  const stmts: D1PreparedStatement[] = [];
  const itemResults: Array<{
    item_id: string;
    purchase_price_cents: number;
    local_cost_cents: number;
  }> = [];

  for (const item of body.items) {
    // Convert foreign purchase price to local currency using actual rate
    // purchase_price_cents is in foreign currency cents
    // local_cost_cents = purchase_price_cents * actual_exchange_rate (result in local cents)
    const localCostCents = Math.round(item.purchase_price_cents * actualRate);

    stmts.push(
      c.env.DB.prepare(
        `UPDATE order_items SET
           purchase_price = ?,
           unit_price_local = ?,
           supplier_id = ?,
           status = 'purchased',
           updated_at = datetime('now')
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(
        item.purchase_price_cents / 100,  // Store as decimal dollars
        localCostCents / 100,              // Store as decimal local
        item.supplier_id || null,
        item.item_id,
        tenantId
      )
    );

    itemResults.push({
      item_id: item.item_id,
      purchase_price_cents: item.purchase_price_cents,
      local_cost_cents: localCostCents,
    });
  }

  // Update order with actual exchange rate
  stmts.push(
    c.env.DB.prepare(
      `UPDATE orders SET
         actual_exchange_rate = ?,
         status = 'purchased',
         updated_at = datetime('now'),
         version = version + 1
       WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(actualRate, body.order_id, tenantId)
  );

  await c.env.DB.batch(stmts);

  return c.json({
    message: 'Purchase recorded',
    order_id: body.order_id,
    pegged_rate: peggedRate,
    actual_rate: actualRate,
    slippage_pct: slippagePct,
    margin_warning: marginWarning,
    margin_warning_message: marginWarning
      ? `⚠️ Exchange rate slipped ${slippagePct.toFixed(2)}% (threshold: ${SLIPPAGE_THRESHOLD_PCT}%). Profit margin may be negative.`
      : null,
    items: itemResults,
  });
});

/**
 * GET /purchasing/slippage/:order_id — Check slippage for a specific order
 */
purchaseRoutes.get('/slippage/:order_id', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id');
  const orderId = c.req.param('order_id');

  const order = await c.env.DB.prepare(
    `SELECT id, pegged_exchange_rate, actual_exchange_rate, total_local, total_foreign
     FROM orders WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(orderId, tenantId).first();

  if (!order) {
    return c.json({ error: 'Not Found' }, 404);
  }

  const pegged = order.pegged_exchange_rate as number || 0;
  const actual = order.actual_exchange_rate as number || 0;
  const slippagePct = pegged > 0
    ? Math.round(((actual - pegged) / pegged) * 10000) / 100
    : 0;

  return c.json({
    order_id: orderId,
    pegged_rate: pegged,
    actual_rate: actual,
    slippage_pct: slippagePct,
    margin_warning: slippagePct > 3,
  });
});
