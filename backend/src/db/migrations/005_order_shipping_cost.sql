-- Migration 005: Add shipping_cost_foreign to orders
-- Stores the direct shipping cost (in USD) for per-order profit calculation.
ALTER TABLE orders ADD COLUMN shipping_cost_foreign REAL DEFAULT 0;
