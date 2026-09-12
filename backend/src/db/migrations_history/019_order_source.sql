-- Migration 019: Order-level source_name
--
-- Adds source_name to orders so a purchasing session can lock in
-- "all items on this order came from Shein" once, and items with a
-- NULL source_name inherit the order-level value on the client.
--
-- Applied to remote D1 as a single ALTER TABLE statement.

ALTER TABLE orders ADD COLUMN source_name TEXT;
