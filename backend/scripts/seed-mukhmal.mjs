/**
 * Seed script: generate INSERT statements for the Mukhmal tenant and super admin.
 * Run: node backend/scripts/seed-mukhmal.mjs
 * Then execute the printed SQL against D1:
 *   wrangler d1 execute estore-db --remote --command="<statement>"
 */

const PASSWORD = 'ta24682468';
const EMAIL    = 'tahamax028@gmail.com';
const NAME     = 'Hazem — مخمل';

async function hashPassword(password) {
  const encoder = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMaterial = await crypto.subtle.importKey(
    'raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']
  );
  const derivedBits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    keyMaterial, 256
  );
  const hash = new Uint8Array(derivedBits);
  const saltHex = Array.from(salt).map(b => b.toString(16).padStart(2, '0')).join('');
  const hashHex = Array.from(hash).map(b => b.toString(16).padStart(2, '0')).join('');
  return `${saltHex}:${hashHex}`;
}

const tenantId = crypto.randomUUID();
const userId   = crypto.randomUUID();
const hash     = await hashPassword(PASSWORD);

console.log('-- Run these two commands one at a time:');
console.log('');
console.log(`INSERT OR IGNORE INTO tenants (id, name, slug, created_at, updated_at, version) VALUES ('${tenantId}', 'مخمل', 'mukhmal', datetime('now'), datetime('now'), 1);`);
console.log('');
console.log(`INSERT OR IGNORE INTO users (id, tenant_id, email, password_hash, full_name, role, created_at, updated_at, version) VALUES ('${userId}', '${tenantId}', '${EMAIL}', '${hash}', '${NAME}', 'super_admin', datetime('now'), datetime('now'), 1);`);
