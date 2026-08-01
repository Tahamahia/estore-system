ALTER TABLE order_items ADD COLUMN written_off_settlement_id TEXT REFERENCES settlements(id);
CREATE INDEX IF NOT EXISTS idx_items_writeoff ON order_items(written_off_settlement_id);
DROP TABLE IF EXISTS local_inventory;
