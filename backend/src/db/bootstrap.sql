-- ============================================================
-- eStore Fulfillment System — Production Bootstrap Script
-- Run ONCE on a fresh D1 database to create the first tenant
-- and super admin user.
-- ============================================================

-- 1. Create default tenant
INSERT OR IGNORE INTO tenants (id, name, slug, created_at, updated_at, version)
VALUES (
  'tenant-default',
  'eStore Main',
  'estore-main',
  datetime('now'),
  datetime('now'),
  1
);

-- 2. Create super admin user
-- Password: SuperAdmin2026!
-- PBKDF2-SHA256 hash generated externally.
-- NOTE: The /api/v1/auth/register endpoint should be used instead
-- for proper password hashing. This SQL is a FALLBACK.
-- Use the curl command below instead:
--
-- RECOMMENDED METHOD (use this command in your terminal):
-- ─────────────────────────────────────────────────────────
-- curl -X POST https://YOUR_WORKER_URL/api/v1/auth/register \
--   -H "Content-Type: application/json" \
--   -d '{
--     "id": "admin-super-001",
--     "email": "admin@estore.ly",
--     "password": "SuperAdmin2026!",
--     "full_name": "Super Administrator",
--     "tenant_id": "tenant-default",
--     "role": "super_admin"
--   }'
-- ─────────────────────────────────────────────────────────

-- 3. Create a default supplier
INSERT OR IGNORE INTO suppliers (id, tenant_id, name, platform, created_at, updated_at, version)
VALUES (
  'sup-taobao-default',
  'tenant-default',
  'Taobao Direct',
  'taobao',
  datetime('now'),
  datetime('now'),
  1
);

INSERT OR IGNORE INTO suppliers (id, tenant_id, name, platform, created_at, updated_at, version)
VALUES (
  'sup-1688-default',
  'tenant-default',
  '1688 Wholesale',
  '1688',
  datetime('now'),
  datetime('now'),
  1
);
