-- ═══════════════════════════════════════════════════════════
-- eStore Fulfillment System — Database Schema
-- Cloudflare D1 (SQLite)
-- ═══════════════════════════════════════════════════════════
-- Rules enforced:
--   • UUID v4 primary keys (client-generated)
--   • tenant_id on EVERY table (multi-tenant RLS)
--   • Soft deletes (is_deleted, deleted_by, deleted_at)
--   • OCC via version column
--   • Composite keys where needed (recycled tracking)
-- ═══════════════════════════════════════════════════════════

-- ─── Tenants (Stores) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenants (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  logo_url TEXT,
  default_currency TEXT DEFAULT 'USD',
  settings TEXT, -- JSON blob for tenant-specific config
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1
);

-- ─── Users ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
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
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE INDEX IF NOT EXISTS idx_users_tenant ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ─── Customers ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT,
  phone2 TEXT,
  address TEXT,
  city TEXT,
  notes TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE INDEX IF NOT EXISTS idx_customers_tenant ON customers(tenant_id);

-- ─── Customer Wallets ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS customer_wallets (
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
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_customer ON customer_wallets(customer_id, tenant_id);

-- ─── Wallet Transactions ──────────────────────────────────
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  wallet_id TEXT NOT NULL,
  amount REAL NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('credit', 'debit')),
  reason TEXT,
  reference_id TEXT, -- order_id or item_id that triggered this
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
CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  platform TEXT, -- e.g. 'taobao', '1688', 'alibaba'
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

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON suppliers(tenant_id);

-- ─── Orders ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  platform TEXT, -- 'manual', 'shopify', 'woocommerce', etc.
  platform_order_id TEXT,
  pegged_exchange_rate REAL, -- rate at order creation
  actual_exchange_rate REAL, -- rate at actual purchase
  currency TEXT DEFAULT 'USD',
  status TEXT NOT NULL DEFAULT 'pending_payment'
    CHECK (status IN (
      'pending_payment', 'paid', 'purchasing', 'purchased',
      'shipped', 'arrived_warehouse', 'sorting', 'sorted',
      'ready_dispatch', 'dispatched', 'delivered',
      'cancelled', 'auto_cancelled', 'refunded'
    )),
  total_foreign REAL DEFAULT 0,
  total_local REAL DEFAULT 0,
  delivery_fee REAL DEFAULT 0,
  notes TEXT,
  created_by TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE INDEX IF NOT EXISTS idx_orders_tenant ON orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status, tenant_id);

-- ─── Order Items (Each piece gets a unique row) ───────────
CREATE TABLE IF NOT EXISTS order_items (
  id TEXT PRIMARY KEY, -- Unique Item UID
  tenant_id TEXT NOT NULL,
  order_id TEXT NOT NULL,
  item_uid TEXT, -- Printable barcode/QR UID assigned during sorting
  shipment_id TEXT,
  product_name TEXT NOT NULL,
  product_url TEXT,
  product_image_url TEXT, -- R2 URL (never base64)
  product_thumb_url TEXT, -- R2 thumbnail URL
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_price_foreign REAL DEFAULT 0,
  unit_price_local REAL DEFAULT 0,
  purchase_price REAL, -- Actual purchase price (entered by purchaser)
  color TEXT,
  size TEXT,
  sku TEXT,                        -- Physical barcode SKU (Shein/Trendyol serial number)
  actual_weight REAL,
  volumetric_weight REAL,
  landed_cost REAL, -- Calculated pro-rata share of master shipment costs
  net_profit REAL, -- Calculated: sell_price - purchase_price - landed_cost
  supplier_id TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending', 'purchased', 'shipped', 'arrived_warehouse',
      'sorted', 'ready_dispatch', 'dispatched', 'delivered',
      'cancelled', 'refunded', 'transferred_to_inventory'
    )),
  sorted_at TEXT,
  dispatched_at TEXT,
  delivered_at TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (shipment_id) REFERENCES shipments(id),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
);

CREATE INDEX IF NOT EXISTS idx_items_tenant ON order_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_items_order ON order_items(order_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_items_shipment ON order_items(shipment_id);
CREATE INDEX IF NOT EXISTS idx_items_uid ON order_items(item_uid);
CREATE INDEX IF NOT EXISTS idx_items_sku ON order_items(sku, tenant_id);
CREATE INDEX IF NOT EXISTS idx_items_status ON order_items(status, tenant_id);

-- ─── Master Shipments ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS master_shipments (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL, -- e.g. "Air Freight June 2025"
  customs_cost REAL DEFAULT 0,
  freight_cost REAL DEFAULT 0,
  other_costs REAL DEFAULT 0,
  total_weight REAL DEFAULT 0,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_transit', 'arrived', 'processed')),
  created_by TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ─── Shipments (Tracking-level) ───────────────────────────
-- Composite uniqueness: tracking_number + supplier_id + ship_date
-- (Chinese tracking numbers recycle)
CREATE TABLE IF NOT EXISTS shipments (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  tracking_number TEXT NOT NULL,
  supplier_id TEXT,
  ship_date TEXT NOT NULL,
  master_shipment_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_transit', 'arrived', 'processed')),
  created_by TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
  FOREIGN KEY (master_shipment_id) REFERENCES master_shipments(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_shipment_composite 
  ON shipments(tracking_number, supplier_id, ship_date, tenant_id);
CREATE INDEX IF NOT EXISTS idx_shipments_master ON shipments(master_shipment_id);

-- ─── Unassigned Items (Lost & Found / Orphaned Packages) ──
CREATE TABLE IF NOT EXISTS unassigned_items (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  barcode TEXT,
  description TEXT,
  photo_url TEXT,
  assigned_to_item_id TEXT, -- Once identified, link here
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'identified', 'assigned', 'disposed')),
  logged_by TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ─── Local Inventory (Dead Stock) ─────────────────────────
CREATE TABLE IF NOT EXISTS local_inventory (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  original_item_id TEXT,
  product_name TEXT NOT NULL,
  purchase_price REAL DEFAULT 0,
  sell_price REAL,
  status TEXT NOT NULL DEFAULT 'available'
    CHECK (status IN ('available', 'sold', 'disposed')),
  reason TEXT, -- 'cancelled', 'refused', 'damaged'
  transferred_by TEXT,
  sold_to TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (original_item_id) REFERENCES order_items(id)
);

-- ─── Exchange Rates ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS exchange_rates (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  from_currency TEXT NOT NULL,
  to_currency TEXT NOT NULL,
  rate REAL NOT NULL,
  set_by TEXT,
  is_deleted INTEGER DEFAULT 0,
  deleted_by TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ─── Audit Log ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  user_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  old_values TEXT, -- JSON
  new_values TEXT, -- JSON
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_tenant ON audit_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity_type, entity_id);
