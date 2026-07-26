INSERT INTO tenants (id, name, slug, default_currency, created_at, updated_at, version)
VALUES ('tenant-001', 'eStore', 'estore', 'LYD', datetime('now'), datetime('now'), 1);

INSERT INTO users (id, tenant_id, email, password_hash, full_name, role, created_at, updated_at, version)
VALUES ('admin-001', 'tenant-001', 'staff@estore.com',
  'e3f1a2b4c6d8e0f2a4b6c8d0e2f4a6b8:cd76280416c940e7c9161d7c6a52a474504c6a134d0b8a7a7bf54d3847cb3ba8',
  'Super Admin', 'super_admin', datetime('now'), datetime('now'), 1);
