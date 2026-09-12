-- Migration 017: Restore orders.internal_shipment_id
--
-- Migration 014 (status_cleanup_and_split) recreated the orders table
-- as orders_v2 and dropped/renamed it, losing the internal_shipment_id
-- column that had been added by the internal shipments feature.
-- This migration restores it via ALTER TABLE (applied manually via wrangler
-- on 2026-08-02 because D1 does not support multi-statement DDL in migrations
-- that include DROP/RENAME TABLE sequences).
--
-- internal_shipments.notes was already present in the original CREATE TABLE
-- from migration 011 — no action needed for that column.

ALTER TABLE orders ADD COLUMN internal_shipment_id TEXT;
