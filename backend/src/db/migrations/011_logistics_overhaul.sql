-- Migration 011: Logistics Overhaul
-- Replace generic shipments hierarchy with two dedicated flows:
--   External Shipments (inbound/import — tracked by courier API)
--   Internal Shipments (outbound/local delivery manifests)

DROP TABLE IF EXISTS shipments;
DROP TABLE IF EXISTS master_shipments;

CREATE TABLE IF NOT EXISTS external_shipments (
  id             TEXT     PRIMARY KEY,
  tenant_id      TEXT     NOT NULL,
  tracking_number TEXT,
  courier_code   TEXT,
  api_status     TEXT     DEFAULT 'unknown',
  manual_status  TEXT     NOT NULL DEFAULT 'in_transit'
    CHECK (manual_status IN ('in_transit', 'at_local_forwarder', 'arrived_at_warehouse')),
  notes          TEXT,
  created_at     DATETIME DEFAULT (datetime('now')),
  updated_at     DATETIME DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS internal_shipments (
  id               TEXT     PRIMARY KEY,
  tenant_id        TEXT     NOT NULL,
  delivery_company TEXT,
  status           TEXT     NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'at_delivery_warehouse', 'out_for_delivery', 'delivered', 'returned')),
  notes            TEXT,
  created_at       DATETIME DEFAULT (datetime('now')),
  updated_at       DATETIME DEFAULT (datetime('now'))
);

ALTER TABLE order_items ADD COLUMN external_shipment_id TEXT REFERENCES external_shipments(id);
ALTER TABLE orders      ADD COLUMN internal_shipment_id TEXT REFERENCES internal_shipments(id);
