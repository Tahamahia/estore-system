-- Migration 003: Fix super-admin password hash
-- The bootstrap.sql originally seeded a bcrypt hash which is incompatible
-- with the PBKDF2 Web Crypto verifier in auth.ts.
-- This migration replaces it with the correct PBKDF2 saltHex:hashHex format.
-- Password: Admin123!
UPDATE users
SET password_hash = 'e3f1a2b4c6d8e0f2a4b6c8d0e2f4a6b8:cd76280416c940e7c9161d7c6a52a474504c6a134d0b8a7a7bf54d3847cb3ba8',
    updated_at = datetime('now'),
    version = version + 1
WHERE id = 'admin-001'
  AND email = 'staff@estore.com';
