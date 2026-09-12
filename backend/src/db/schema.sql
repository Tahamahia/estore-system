-- ═══════════════════════════════════════════════════════════
-- eStore Fulfillment System — Canonical Schema (Cloudflare D1 / SQLite)
--
-- This file is the canonical schema for fresh installs. Migrations
-- 001–022 are historical and must NOT be replayed on top of it.
--
-- Regenerated from the live remote database on 2026-09-12 after Phase 4
-- consolidated duplicate columns and dropped dead ones. To keep this file
-- honest, re-transcribe from remote whenever a new migration lands:
--
--   npx wrangler d1 execute estore-db --remote \
--     --command "SELECT sql FROM sqlite_master \
--                WHERE type IN ('table','index') AND sql IS NOT NULL \
--                ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name"
--
-- Rules the schema enforces:
--   • UUID v4 primary keys (client-generated)
--   • tenant_id on every business table (multi-tenant isolation)
--   • Soft deletes (is_deleted, deleted_by, deleted_at)
--   • OCC via version column where writes race
--
-- Deliberate omissions from the live snapshot (not part of a fresh install):
--   • `_cf_KV` and `sqlite_sequence` — D1 / SQLite internal tables.
--   • `orders_old` and its indexes — historical debris from migration 014's
--     table rebuild; nothing reads or writes it.
-- ═══════════════════════════════════════════════════════════

-- ─── Tenants ───────────────────────────────────────────────
CREATE TABLE tenants (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  logo_url TEXT,
  default_currency TEXT DEFAULT 'USD',
  settings TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1
);

-- ─── Users ─────────────────────────────────────────────────
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'store_manager', 'purchaser', 'sorter', 'driver')),
  phone TEXT,
  is_active INTEGER DEFAULT 1,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('pending', 'active', 'rejected')),
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_users_email  ON users(email);
CREATE INDEX idx_users_tenant ON users(tenant_id);

-- ─── Customers ─────────────────────────────────────────────
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT,
  phone2 TEXT,
  address TEXT,
  city TEXT,
  area TEXT,
  street TEXT,
  location_url TEXT,
  notes TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_customers_tenant ON customers(tenant_id);
CREATE UNIQUE INDEX idx_customers_phone_tenant
  ON customers(phone, tenant_id)
  WHERE phone IS NOT NULL AND is_deleted = 0;

-- ─── Customer Wallets ──────────────────────────────────────
CREATE TABLE customer_wallets (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  balance REAL NOT NULL DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE INDEX idx_customer_wallets_customer_id ON customer_wallets(customer_id);
CREATE UNIQUE INDEX idx_wallet_customer       ON customer_wallets(customer_id, tenant_id);

-- ─── Wallet Transactions ───────────────────────────────────
CREATE TABLE wallet_transactions (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  wallet_id TEXT NOT NULL,
  amount REAL NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('credit', 'debit')),
  reason TEXT,
  reference_id TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (wallet_id) REFERENCES customer_wallets(id)
);

-- ─── Suppliers ─────────────────────────────────────────────
CREATE TABLE suppliers (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  platform TEXT,
  contact_info TEXT,
  notes TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_suppliers_tenant ON suppliers(tenant_id);

-- ─── Settlements ───────────────────────────────────────────
CREATE TABLE settlements (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  exchange_rate REAL NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ─── External Shipments (courier-tracked incoming parcels) ─
CREATE TABLE external_shipments (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  tracking_number TEXT,
  courier_code    TEXT,
  api_status      TEXT DEFAULT 'unknown',
  manual_status   TEXT NOT NULL DEFAULT 'in_transit'
    CHECK (manual_status IN ('in_transit', 'at_local_forwarder', 'arrived_at_warehouse')),
  notes           TEXT,
  created_at      DATETIME DEFAULT (datetime('now')),
  updated_at      DATETIME DEFAULT (datetime('now')),
  received_at     TEXT
);

-- ─── Internal Shipments (last-mile delivery manifests) ────
CREATE TABLE internal_shipments (
  id                   TEXT PRIMARY KEY,
  tenant_id            TEXT NOT NULL,
  delivery_company     TEXT,
  status               TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'at_delivery_warehouse', 'out_for_delivery', 'delivered', 'returned')),
  notes                TEXT,
  created_at           DATETIME DEFAULT (datetime('now')),
  updated_at           DATETIME DEFAULT (datetime('now')),
  driver_name          TEXT,
  cash_handed_over     REAL,
  cash_handed_over_at  TEXT
);

-- ─── Orders ────────────────────────────────────────────────
CREATE TABLE "orders" (
  id                    TEXT PRIMARY KEY,
  tenant_id             TEXT NOT NULL,
  customer_id           TEXT NOT NULL,
  platform              TEXT,
  platform_order_id     TEXT,
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
  internal_shipment_id  TEXT,
  deposit_amount        REAL NOT NULL DEFAULT 0,
  deposit_note          TEXT,
  cash_collected        REAL NOT NULL DEFAULT 0,
  cash_collected_at     TEXT,
  source_name           TEXT,
  FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE INDEX idx_orders_parent ON orders(parent_order_id);

-- ─── Order Items ───────────────────────────────────────────
CREATE TABLE "order_items" (
  id                          TEXT PRIMARY KEY,
  tenant_id                   TEXT NOT NULL,
  order_id                    TEXT,
  shipment_id                 TEXT,
  product_name                TEXT NOT NULL,
  product_url                 TEXT,
  product_image_url           TEXT,
  quantity                    INTEGER NOT NULL DEFAULT 1,
  unit_price_foreign          REAL DEFAULT 0,
  unit_price_local            REAL DEFAULT 0,
  color                       TEXT,
  size                        TEXT,
  sku                         TEXT,
  actual_weight               REAL,
  volumetric_weight           REAL,
  supplier_id                 TEXT,   -- dormant post-Phase-4 (FK-blocked DROP, always NULL, unreferenced by code)
  notes                       TEXT,
  status                      TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending','purchased','shipped','arrived_warehouse','sorted',
      'ready_dispatch','dispatched','delivered','cancelled','refunded',
      'transferred_to_inventory','in_stock'
    )),
  sorted_at                   TEXT,
  dispatched_at               TEXT,
  delivered_at                TEXT,
  is_deleted                  INTEGER DEFAULT 0,
  deleted_by                  TEXT,
  deleted_at                  TEXT,
  created_at                  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at                  TEXT NOT NULL DEFAULT (datetime('now')),
  version                     INTEGER NOT NULL DEFAULT 1,
  weight                      REAL DEFAULT 0,
  brand                       TEXT,
  source_name                 TEXT,
  shipping_rate_per_kg        REAL DEFAULT 0,
  external_shipment_id        TEXT REFERENCES external_shipments(id),
  category                    TEXT,
  attributes                  TEXT,
  cost_usd                    REAL,
  written_off_settlement_id   TEXT REFERENCES settlements(id),
  FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
  FOREIGN KEY (order_id)    REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
);
CREATE INDEX idx_items_tenant   ON order_items(tenant_id);
CREATE INDEX idx_items_order    ON order_items(order_id, tenant_id);
CREATE INDEX idx_items_shipment ON order_items(shipment_id);
CREATE INDEX idx_items_sku      ON order_items(sku, tenant_id);
CREATE INDEX idx_items_status   ON order_items(status, tenant_id);
CREATE INDEX idx_items_writeoff ON order_items(written_off_settlement_id);

-- ─── Master Shipment Bundles (name/status only in current schema) ─
CREATE TABLE shipments (
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
  version    INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_shipments_tenant ON shipments(tenant_id);

-- ─── Shipping Sources (global — no tenant_id; shared catalog) ─
CREATE TABLE shipping_sources (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  rate_per_kg REAL NOT NULL DEFAULT 0
);

-- ─── Unassigned Items (orphaned scans / lost-and-found) ────
CREATE TABLE unassigned_items (
  id                  TEXT PRIMARY KEY,
  tenant_id           TEXT NOT NULL,
  barcode             TEXT,
  description         TEXT,
  photo_url           TEXT,
  assigned_to_item_id TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'identified', 'assigned', 'disposed')),
  logged_by           TEXT,
  is_deleted          INTEGER DEFAULT 0,
  deleted_by          TEXT,
  deleted_at          TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  version             INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ─── Exchange Rates ────────────────────────────────────────
CREATE TABLE exchange_rates (
  id            TEXT PRIMARY KEY,
  tenant_id     TEXT NOT NULL,
  from_currency TEXT NOT NULL,
  to_currency   TEXT NOT NULL,
  rate          REAL NOT NULL,
  set_by        TEXT,
  is_deleted    INTEGER DEFAULT 0,
  deleted_by    TEXT,
  deleted_at    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  version       INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ─── Audit Log ─────────────────────────────────────────────
CREATE TABLE audit_log (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL,
  user_id     TEXT,
  action      TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id   TEXT NOT NULL,
  old_values  TEXT,
  new_values  TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_tenant ON audit_log(tenant_id);
