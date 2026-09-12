-- Migration 020: external_shipments.received_at
--
-- Fixes a logical dead-end in the reconciliation model introduced in
-- migration/logic from Phase 3: POST /:id/receive was cascading every
-- 'shipped' item to 'arrived_warehouse', which made missing_count
-- (defined as items still in 'shipped' after receive) always 0. The
-- mark-lost path was therefore unreachable.
--
-- New model:
--   - received_at = timestamp set when the boxes physically arrive.
--   - Items are PRESUMED present (arrived_warehouse) once received.
--   - The scanner PROVES presence (sorted).
--   - Missing = presumed-present items never proven by a scan.
--
-- Applied to remote D1 as a single ALTER TABLE statement.

ALTER TABLE external_shipments ADD COLUMN received_at TEXT;
