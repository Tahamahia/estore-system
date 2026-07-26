-- Migration 004: Add missing performance indexes
-- These foreign-key columns are queried on every customer dispatch lookup,
-- order detail fetch, and wallet balance check but had no covering index.
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
  ON orders(customer_id);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON order_items(order_id);

CREATE INDEX IF NOT EXISTS idx_customer_wallets_customer_id
  ON customer_wallets(customer_id);
