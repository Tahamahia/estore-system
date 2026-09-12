-- Migration 007: Weight-based dynamic shipping and item categorization
-- shipping_rate_per_kg on orders drives per-item shipping cost calculation.
-- item_category, weight, and brand on order_items support the categorized item dialog.
ALTER TABLE orders ADD COLUMN shipping_rate_per_kg REAL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN item_category TEXT;
ALTER TABLE order_items ADD COLUMN weight REAL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN brand TEXT;
