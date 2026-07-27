-- Migration 012: Add in_stock status to order_items and allow NULL order_id for orphaned items
-- Run each statement individually:
-- 1. npx wrangler d1 execute estore-db --remote --command="CREATE TABLE ..."
-- ...etc

-- Statement 1: Create new table
CREATE TABLE order_items_new (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  order_id TEXT,
  item_uid TEXT,
  shipment_id TEXT,
  product_name TEXT NOT NULL,
  product_url TEXT,
  product_image_url TEXT,
  product_thumb_url TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_price_foreign REAL DEFAULT 0,
  unit_price_local REAL DEFAULT 0,
  purchase_price REAL,
  color TEXT,
  size TEXT,
  sku TEXT,
  actual_weight REAL,
  volumetric_weight REAL,
  landed_cost REAL,
  net_profit REAL,
  supplier_id TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending','purchased','shipped','arrived_warehouse',
      'sorted','ready_dispatch','dispatched','delivered',
      'cancelled','refunded','transferred_to_inventory','in_stock'
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
  shipping_cost_foreign REAL DEFAULT 0,
  item_category TEXT,
  weight REAL DEFAULT 0,
  brand TEXT,
  source_name TEXT,
  shipping_rate_per_kg REAL DEFAULT 0,
  external_shipment_id TEXT REFERENCES external_shipments(id),
  FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
);

-- Statement 2: Copy data
INSERT INTO order_items_new (id,tenant_id,order_id,item_uid,shipment_id,product_name,product_url,product_image_url,product_thumb_url,quantity,unit_price_foreign,unit_price_local,purchase_price,color,size,sku,actual_weight,volumetric_weight,landed_cost,net_profit,supplier_id,notes,status,sorted_at,dispatched_at,delivered_at,is_deleted,deleted_by,deleted_at,created_at,updated_at,version,shipping_cost_foreign,item_category,weight,brand,source_name,shipping_rate_per_kg,external_shipment_id)
SELECT id,tenant_id,order_id,item_uid,shipment_id,product_name,product_url,product_image_url,product_thumb_url,quantity,unit_price_foreign,unit_price_local,purchase_price,color,size,sku,actual_weight,volumetric_weight,landed_cost,net_profit,supplier_id,notes,status,sorted_at,dispatched_at,delivered_at,is_deleted,deleted_by,deleted_at,created_at,updated_at,version,shipping_cost_foreign,item_category,weight,brand,source_name,shipping_rate_per_kg,external_shipment_id FROM order_items;

-- Statement 3:
DROP TABLE order_items;

-- Statement 4:
ALTER TABLE order_items_new RENAME TO order_items;

-- Statement 5:
CREATE INDEX IF NOT EXISTS idx_items_tenant ON order_items(tenant_id);

-- Statement 6:
CREATE INDEX IF NOT EXISTS idx_items_order ON order_items(order_id, tenant_id);

-- Statement 7:
CREATE INDEX IF NOT EXISTS idx_items_shipment ON order_items(shipment_id);

-- Statement 8:
CREATE INDEX IF NOT EXISTS idx_items_uid ON order_items(item_uid);

-- Statement 9:
CREATE INDEX IF NOT EXISTS idx_items_sku ON order_items(sku, tenant_id);

-- Statement 10:
CREATE INDEX IF NOT EXISTS idx_items_status ON order_items(status, tenant_id);
