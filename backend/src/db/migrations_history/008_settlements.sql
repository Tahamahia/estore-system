-- Migration 008: Bulk financial settlements (تسكيرة حساب)
-- Groups orders into a settlement batch with a fixed exchange rate for true USD P&L.
CREATE TABLE settlements (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  exchange_rate REAL NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE orders ADD COLUMN settlement_id TEXT REFERENCES settlements(id);
