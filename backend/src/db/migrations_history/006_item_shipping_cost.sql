-- Migration 006: Add shipping_cost_foreign to order_items
-- Stores per-item shipping cost (in USD) for granular profit calculation.
ALTER TABLE order_items ADD COLUMN shipping_cost_foreign REAL DEFAULT 0;
