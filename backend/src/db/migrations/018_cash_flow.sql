-- Migration 018: Cash-flow tracking
--
-- Adds fields for the missing cash-flow gap:
--   1. Deposits taken by the store at order time (عربون).
--   2. Cash collected by the delivery driver on delivery.
--   3. Cash handed over from the driver to the store per manifest.
--
-- Delivery fees are paid by the customer directly to the delivery
-- company, so they are NEITHER store revenue nor store cost. They are
-- intentionally NOT tracked here.
--
-- Applied on remote D1 statement-by-statement (D1 does not accept
-- multi-statement ALTER TABLE files in one shot).

ALTER TABLE orders ADD COLUMN deposit_amount REAL NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN deposit_note TEXT;
ALTER TABLE orders ADD COLUMN cash_collected REAL NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN cash_collected_at TEXT;

ALTER TABLE internal_shipments ADD COLUMN driver_name TEXT;
ALTER TABLE internal_shipments ADD COLUMN cash_handed_over REAL;
ALTER TABLE internal_shipments ADD COLUMN cash_handed_over_at TEXT;
