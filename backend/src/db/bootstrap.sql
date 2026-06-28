INSERT INTO tenants (id, name, slug, default_currency, created_at, updated_at, version)
VALUES ('tenant-001', 'eStore', 'estore', 'LYD', datetime('now'), datetime('now'), 1);

INSERT INTO users (id, tenant_id, email, password_hash, full_name, role, created_at, updated_at, version)
VALUES ('admin-001', 'tenant-001', 'staff@estore.com', 
  '$2b$10$p8cNsvyIq0Aw4Dl3T0ZFM.CfkdOYk0frLrzTDo4btL2YgRZqRvLgO', 
  'Super Admin', 'super_admin', datetime('now'), datetime('now'), 1);
