-- Migration 023: Lost-item expensing + deposit fate on cancellation
--
-- 1. order_items.lost_at — stamped by POST /external-shipments/:id/items/
--    :itemId/mark-lost alongside the 'cancelled' status. Settlement creation
--    ALWAYS writes these off (stamps written_off_settlement_id) so the cost of
--    a piece the courier lost is expensed instead of silently disappearing
--    with the cancelled status.
-- 2. orders.deposit_status — what happened to the deposit (عربون) of a
--    cancelled order: 'refunded' to the customer, or 'forfeited' (kept by the
--    store, counted as revenue in the settlement that picks it up via
--    forfeited_order_ids). NULL = undecided. 'held' is reserved for a live
--    order's deposit.
--
-- Applied on remote D1 statement-by-statement.

ALTER TABLE order_items ADD COLUMN lost_at TEXT;
ALTER TABLE orders ADD COLUMN deposit_status TEXT CHECK (deposit_status IN ('held','refunded','forfeited'));
