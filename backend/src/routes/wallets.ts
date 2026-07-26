import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const walletRoutes = new Hono<AppEnv>();

/**
 * GET /wallets/:customer_id — Get wallet balance and recent transactions
 */
walletRoutes.get('/:customer_id', async (c) => {
  const tenantId = c.get('tenant_id');
  const customerId = c.req.param('customer_id');

  const wallet = await c.env.DB.prepare(
    `SELECT * FROM customer_wallets
     WHERE customer_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(customerId, tenantId).first();

  if (!wallet) {
    return c.json({ customer_id: customerId, balance_cents: 0, transactions: [] });
  }

  const transactions = await c.env.DB.prepare(
    `SELECT * FROM wallet_transactions
     WHERE wallet_id = ? AND tenant_id = ? AND is_deleted = 0
     ORDER BY created_at DESC LIMIT 50`
  ).bind(wallet.id, tenantId).all();

  return c.json({
    customer_id: customerId,
    wallet_id: wallet.id,
    balance_cents: Math.round(((wallet.balance as number) || 0) * 100),
    balance: wallet.balance,
    transactions: transactions.results,
  });
});

/**
 * POST /wallets/credit — Credit a customer's wallet
 * 
 * Used when a supplier cancels an item — credit the missing item's value
 * to the customer's wallet for future use or refund.
 */
walletRoutes.post('/credit', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const userId = c.get('user_id');
  const body = await c.req.json<{
    customer_id: string;
    amount_cents: number;  // Integer cents
    reason: string;
    reference_id?: string;  // Order or item ID
  }>();

  if (!body.customer_id || !body.amount_cents || body.amount_cents <= 0) {
    return c.json({ error: 'Bad Request', message: 'customer_id and positive amount_cents required' }, 400);
  }

  const amountDecimal = body.amount_cents / 100;
  const stmts: D1PreparedStatement[] = [];

  // Check if wallet exists
  const wallet = await c.env.DB.prepare(
    `SELECT id, balance FROM customer_wallets
     WHERE customer_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(body.customer_id, tenantId).first();

  let walletId: string;

  if (wallet) {
    walletId = wallet.id as string;
    // Update balance
    stmts.push(
      c.env.DB.prepare(
        `UPDATE customer_wallets SET
           balance = balance + ?,
           updated_at = datetime('now'),
           version = version + 1
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(amountDecimal, walletId, tenantId)
    );
  } else {
    // Create wallet
    walletId = crypto.randomUUID();
    stmts.push(
      c.env.DB.prepare(
        `INSERT INTO customer_wallets (id, tenant_id, customer_id, balance, created_at, updated_at, version)
         VALUES (?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
      ).bind(walletId, tenantId, body.customer_id, amountDecimal)
    );
  }

  // Record transaction
  const txId = crypto.randomUUID();
  stmts.push(
    c.env.DB.prepare(
      `INSERT INTO wallet_transactions (id, tenant_id, wallet_id, amount, type, reason, reference_id, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, 'credit', ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(txId, tenantId, walletId, amountDecimal, body.reason || 'Supplier cancellation credit', body.reference_id || null)
  );

  await c.env.DB.batch(stmts);

  return c.json({
    message: 'Wallet credited',
    wallet_id: walletId,
    credit_amount_cents: body.amount_cents,
    transaction_id: txId,
  });
});

/**
 * POST /wallets/debit — Debit from wallet (apply credit to a new order)
 */
walletRoutes.post('/debit', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    customer_id: string;
    amount_cents: number;
    reason: string;
    reference_id?: string;
  }>();

  if (!body.customer_id || !body.amount_cents || body.amount_cents <= 0) {
    return c.json({ error: 'Bad Request', message: 'customer_id and positive amount_cents required' }, 400);
  }

  const wallet = await c.env.DB.prepare(
    `SELECT id, balance, version FROM customer_wallets
     WHERE customer_id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(body.customer_id, tenantId).first();

  if (!wallet) {
    return c.json({ error: 'Bad Request', message: 'Customer has no wallet' }, 400);
  }

  const balanceCents = Math.round(((wallet.balance as number) || 0) * 100);
  if (body.amount_cents > balanceCents) {
    return c.json({
      error: 'Insufficient Balance',
      message: `Wallet balance: ${balanceCents} cents, requested: ${body.amount_cents} cents`,
      balance_cents: balanceCents,
    }, 400);
  }

  const amountDecimal = body.amount_cents / 100;
  const txId = crypto.randomUUID();

  // FIX 10: First update wallet with OCC check, verify it succeeded, THEN insert transaction
  const walletUpdate = await c.env.DB.prepare(
    `UPDATE customer_wallets SET
       balance = balance - ?,
       updated_at = datetime('now'),
       version = version + 1
     WHERE id = ? AND tenant_id = ? AND version = ? AND is_deleted = 0`
  ).bind(amountDecimal, wallet.id, tenantId, wallet.version).run();

  if (walletUpdate.meta.changes === 0) {
    return c.json({
      error: 'Conflict',
      message: 'Wallet was modified by another request (version mismatch). Please retry.',
    }, 409);
  }

  // OCC check passed — safe to insert the transaction record
  await c.env.DB.prepare(
    `INSERT INTO wallet_transactions (id, tenant_id, wallet_id, amount, type, reason, reference_id, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, 'debit', ?, ?, datetime('now'), datetime('now'), 1)`
  ).bind(txId, tenantId, wallet.id, amountDecimal, body.reason || 'Applied to order', body.reference_id || null).run();

  return c.json({
    message: 'Wallet debited',
    wallet_id: wallet.id,
    debit_amount_cents: body.amount_cents,
    new_balance_cents: balanceCents - body.amount_cents,
    transaction_id: txId,
  });
});
