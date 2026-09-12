-- Migration 014: Normalize orders.status CHECK constraint + add parent_order_id for order splitting
--
-- The orders table from migration 013 has a bloated CHECK constraint that mixes
-- legacy statuses with new ones and is missing plain 'pending' and
-- 'transferred_to_inventory'. This migration brings it in line with the
-- order_items constraint and the frontend's authoritative 12-value list.
--
-- Run each numbered statement INDIVIDUALLY via:
--   wrangler d1 execute estore-db --remote --command "<statement>"
-- Verify row counts match before and after statements 2-4.

-- ── Statement 1: Create new orders table with correct status constraint ────────
CREATE TABLE orders_v2 (
  id                    TEXT PRIMARY KEY,
  tenant_id             TEXT NOT NULL,
  customer_id           TEXT NOT NULL,
  platform              TEXT,
  platform_order_id     TEXT,
  pegged_exchange_rate   REAL,
  actual_exchange_rate   REAL,
  currency              TEXT DEFAULT 'USD',
  cart_link             TEXT,
  order_type            TEXT NOT NULL DEFAULT 'individual_items'
    CHECK (order_type IN ('full_cart', 'individual_items')),
  total_sale_price_lyd  REAL,
  total_cost_usd        REAL,
  status                TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending','purchased','shipped','arrived_warehouse','sorted',
      'ready_dispatch','dispatched','delivered','cancelled','refunded',
      'transferred_to_inventory','in_stock'
    )),
  total_foreign         REAL DEFAULT 0,
  total_local           REAL DEFAULT 0,
  delivery_fee          REAL DEFAULT 0,
  shipping_cost_foreign REAL DEFAULT 0,
  shipping_rate_per_kg  REAL DEFAULT 0,
  settlement_id         TEXT,
  notes                 TEXT,
  created_by            TEXT,
  is_deleted            INTEGER DEFAULT 0,
  deleted_by            TEXT,
  deleted_at            TEXT,
  created_at            TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at            TEXT NOT NULL DEFAULT (datetime('now')),
  version               INTEGER NOT NULL DEFAULT 1,
  parent_order_id       TEXT,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- ── Statement 2: Copy all rows with status normalization + NULL parent_order_id ─
INSERT INTO orders_v2 (
  id, tenant_id, customer_id, platform, platform_order_id,
  pegged_exchange_rate, actual_exchange_rate, currency,
  cart_link, order_type, total_sale_price_lyd, total_cost_usd,
  status, total_foreign, total_local, delivery_fee,
  shipping_cost_foreign, shipping_rate_per_kg, settlement_id,
  notes, created_by, is_deleted, deleted_by, deleted_at,
  created_at, updated_at, version, parent_order_id
)
SELECT
  id, tenant_id, customer_id, platform, platform_order_id,
  pegged_exchange_rate, actual_exchange_rate, currency,
  cart_link, order_type, total_sale_price_lyd, total_cost_usd,
  CASE status
    WHEN 'pending_purchase'    THEN 'pending'
    WHEN 'pending_payment'     THEN 'pending'
    WHEN 'paid'                THEN 'purchased'
    WHEN 'purchasing'          THEN 'purchased'
    WHEN 'at_overseas_warehouse' THEN 'shipped'
    WHEN 'arrived_in_libya'    THEN 'arrived_warehouse'
    WHEN 'sorting'             THEN 'sorted'
    WHEN 'received_and_priced' THEN 'sorted'
    WHEN 'out_for_delivery'    THEN 'dispatched'
    WHEN 'returned_in_stock'   THEN 'in_stock'
    WHEN 'out_of_stock'        THEN 'cancelled'
    WHEN 'auto_cancelled'      THEN 'cancelled'
    ELSE status
  END,
  total_foreign, total_local, delivery_fee,
  shipping_cost_foreign, shipping_rate_per_kg, settlement_id,
  notes, created_by, is_deleted, deleted_by, deleted_at,
  created_at, updated_at, version, NULL
FROM orders;

-- ── Statement 3: Drop old orders table ────────────────────────────────────────
DROP TABLE orders;

-- ── Statement 4: Rename orders_v2 → orders ────────────────────────────────────
ALTER TABLE orders_v2 RENAME TO orders;

-- ── Statement 5: Recreate idx_orders_tenant ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_tenant ON orders(tenant_id);

-- ── Statement 6: Recreate idx_orders_customer ─────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id, tenant_id);

-- ── Statement 7: Recreate idx_orders_status ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status, tenant_id);

-- ── Statement 8: New index for parent/child order lookups ─────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_parent ON orders(parent_order_id);
