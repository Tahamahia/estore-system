-- Migration 002: Phone-First Customer Identity
-- Adds UNIQUE constraint on (phone, tenant_id) for deduplication.
-- Ensures phone is the primary business identifier per tenant.

-- Create a unique index (phone can be NULL — SQLite allows multiple NULLs in unique indexes)
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_tenant 
  ON customers(phone, tenant_id) 
  WHERE phone IS NOT NULL AND is_deleted = 0;
