-- Migration 013: ERP Architecture Overhaul
-- Adds cart_link / order_type / financial columns to orders,
-- dynamic attributes / cost columns to order_items,
-- and creates a simple shipments grouping table.
--
-- Run each numbered statement individually via wrangler d1 execute.

-- ── Statement 1: Recreate orders with expanded status list + new columns ─────
-- (SQLite cannot ALTER a CHECK constraint; table recreation is required)
CREATE TABLE orders_new (
  id                    TEXT PRIMARY KEY,
  tenant_id             TEXT NOT NULL,
  customer_id           TEXT NOT NULL,
  platform              TEXT,
  platform_order_id     TEXT,
  pegged_exchange_rate   REAL,
  actual_exchange_rate   REAL,
  currency              TEXT DEFAULT 'USD',
  -- ── New ERP fields ────────────────────────────────────────────────────────
  cart_link             TEXT,
  order_type            TEXT NOT NULL DEFAULT 'individual_items'
    CHECK (order_type IN ('full_cart', 'individual_items')),
  total_sale_price_lyd  REAL,
  total_cost_usd        REAL,
  -- ── Status: legacy + new ERP statuses coexist for backward compat ─────────
  status                TEXT NOT NULL DEFAULT 'pending_purchase'
    CHECK (status IN (
      -- New ERP lifecycle
      'pending_purchase', 'purchased', 'at_overseas_warehouse',
      'arrived_in_libya', 'received_and_priced', 'out_for_delivery',
      'delivered', 'returned_in_stock', 'out_of_stock',
      -- Legacy statuses (kept for existing rows)
      'pending_payment', 'paid', 'purchasing', 'shipped',
      'arrived_warehouse', 'sorting', 'sorted',
      'ready_dispatch', 'dispatched', 'cancelled', 'auto_cancelled',
      'refunded', 'in_stock'
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
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- ── Statement 2: Copy existing rows into the new table ────────────────────────
INSERT INTO orders_new (
  id, tenant_id, customer_id, platform, platform_order_id,
  pegged_exchange_rate, actual_exchange_rate, currency,
  cart_link, order_type, total_sale_price_lyd, total_cost_usd,
  status, total_foreign, total_local, delivery_fee,
  shipping_cost_foreign, shipping_rate_per_kg, settlement_id,
  notes, created_by, is_deleted, deleted_by, deleted_at,
  created_at, updated_at, version
)
SELECT
  id, tenant_id, customer_id, platform, platform_order_id,
  pegged_exchange_rate, actual_exchange_rate, currency,
  NULL, 'individual_items', NULL, NULL,
  status, total_foreign, total_local, delivery_fee,
  COALESCE(shipping_cost_foreign, 0), COALESCE(shipping_rate_per_kg, 0), settlement_id,
  notes, created_by, is_deleted, deleted_by, deleted_at,
  created_at, updated_at, version
FROM orders;

-- ── Statement 3: Drop old orders table ────────────────────────────────────────
DROP TABLE orders;

-- ── Statement 4: Rename new table ─────────────────────────────────────────────
ALTER TABLE orders_new RENAME TO orders;

-- ── Statement 5-7: Recreate indexes ───────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_tenant   ON orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status   ON orders(status, tenant_id);

-- ── Statements 8-11: Add new columns to order_items ───────────────────────────
-- SQLite ADD COLUMN is safe (no data loss) and preserves existing rows.
ALTER TABLE order_items ADD COLUMN category   TEXT;
ALTER TABLE order_items ADD COLUMN attributes TEXT;
ALTER TABLE order_items ADD COLUMN sale_price_lyd REAL;
ALTER TABLE order_items ADD COLUMN cost_usd   REAL;

-- ── Statement 12: Create simple shipments grouping table ──────────────────────
CREATE TABLE IF NOT EXISTS shipments (
  id         TEXT PRIMARY KEY,
  tenant_id  TEXT NOT NULL,
  name       TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_transit', 'arrived', 'completed', 'cancelled')),
  notes      TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version    INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ── Statement 13: Index on shipments ──────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_shipments_tenant ON shipments(tenant_id);
