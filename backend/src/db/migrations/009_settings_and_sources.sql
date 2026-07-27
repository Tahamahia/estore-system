-- Migration 009: Shipping sources as settings, per-item shipping rate
-- Moves shipping rate to the item level so each item tracks its own source and cost.
CREATE TABLE shipping_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  rate_per_kg REAL NOT NULL DEFAULT 0
);

INSERT INTO shipping_sources (name, rate_per_kg) VALUES
  ('Shein', 8.5),
  ('AliExpress', 12.0),
  ('Amazon', 15.0);

ALTER TABLE order_items ADD COLUMN source_name TEXT;
ALTER TABLE order_items ADD COLUMN shipping_rate_per_kg REAL DEFAULT 0;
