-- ═══════════════════════════════════════════════════════════
-- Migration: Add SKU column to order_items
-- Required for Shein/Trendyol barcode matching
-- ═══════════════════════════════════════════════════════════

ALTER TABLE order_items ADD COLUMN sku TEXT;

-- Index for fast barcode scanner lookups by SKU
CREATE INDEX IF NOT EXISTS idx_items_sku ON order_items(sku, tenant_id);
