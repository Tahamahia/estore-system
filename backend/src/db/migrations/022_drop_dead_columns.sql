-- Migration 022: Physical drop of duplicate + dead columns
--
-- Prerequisites (already satisfied on remote D1):
--   1. Migration 021 backfilled every winner from its loser.
--   2. Every code path was rewritten (Phase 4 PART B) to read/write only
--      canonical columns.
--   3. A full remote-D1 export was taken and verified before running
--      any DROP: backend/backup_before_021.sql (36 KB, valid SQL).
--
-- Applied one statement at a time on remote D1 (D1's SQLite supports
-- ALTER TABLE DROP COLUMN). idx_items_uid on order_items(item_uid)
-- must be dropped before its column.

DROP INDEX IF EXISTS idx_items_uid;

ALTER TABLE order_items DROP COLUMN sale_price_lyd;
ALTER TABLE order_items DROP COLUMN item_category;
ALTER TABLE order_items DROP COLUMN product_thumb_url;
ALTER TABLE order_items DROP COLUMN shipping_cost_foreign;
ALTER TABLE order_items DROP COLUMN landed_cost;
ALTER TABLE order_items DROP COLUMN purchase_price;
ALTER TABLE order_items DROP COLUMN net_profit;
-- ALTER TABLE order_items DROP COLUMN supplier_id;
--   Deferred. D1's SQLite refuses this because the column is part of a
--   FOREIGN KEY definition (REFERENCES suppliers(id)) and DROP COLUMN
--   would leave a dangling constraint. Confirmed via live run:
--     "unknown column supplier_id in foreign key definition"
--   Removing it requires a full table rebuild (create shadow table
--   without the FK, copy rows, drop old, rename, recreate indexes) —
--   deliberately not done here because (a) 0 rows have a non-NULL
--   supplier_id, verified via SELECT COUNT(*) WHERE supplier_id IS
--   NOT NULL, and (b) no code path reads or writes it. The column is
--   effectively dead but physically kept; a follow-up rebuild migration
--   can remove it if the FK weight ever matters.
ALTER TABLE order_items DROP COLUMN item_uid;

ALTER TABLE orders DROP COLUMN delivery_fee;
ALTER TABLE orders DROP COLUMN total_local;
ALTER TABLE orders DROP COLUMN total_foreign;
ALTER TABLE orders DROP COLUMN pegged_exchange_rate;
ALTER TABLE orders DROP COLUMN actual_exchange_rate;

-- Verify with:
--   PRAGMA table_info(order_items)
--   PRAGMA table_info(orders)
