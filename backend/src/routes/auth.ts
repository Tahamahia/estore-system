import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { generateJWT } from '../middleware/auth';

export const authRoutes = new Hono<AppEnv>();

/**
 * POST /api/v1/auth/login
 * Authenticates a user and returns a JWT.
 */
authRoutes.post('/login', async (c) => {
  const body = await c.req.json<{ email: string; password: string }>();
  const { email, password } = body;

  if (!email || !password) {
    return c.json({ error: 'Bad Request', message: 'Email and password are required' }, 400);
  }

  // Query user by email (parameterized — no SQL injection)
  const user = await c.env.DB.prepare(
    `SELECT id, email, password_hash, tenant_id, role, full_name, is_deleted 
     FROM users 
     WHERE email = ? AND is_deleted = 0`
  ).bind(email).first();

  if (!user) {
    return c.json({ error: 'Unauthorized', message: 'Invalid credentials' }, 401);
  }

  // Verify password using Web Crypto (PBKDF2)
  const isValid = await verifyPassword(password, user.password_hash as string);
  if (!isValid) {
    return c.json({ error: 'Unauthorized', message: 'Invalid credentials' }, 401);
  }

  // Generate JWT
  const token = await generateJWT(
    {
      sub: user.id as string,
      tenant_id: user.tenant_id as string,
      role: user.role as string,
    },
    c.env.JWT_SECRET
  );

  return c.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      role: user.role,
      tenant_id: user.tenant_id,
    },
  });
});

/**
 * POST /api/v1/auth/register (Super Admin only in production)
 * Creates a new user account.
 */
authRoutes.post('/register', async (c) => {
  const body = await c.req.json<{
    id: string; // Client-generated UUID v4
    email: string;
    password: string;
    full_name: string;
    tenant_id: string;
    role: string;
  }>();

  if (!body.id || !body.email || !body.password || !body.full_name || !body.tenant_id || !body.role) {
    return c.json({ error: 'Bad Request', message: 'All fields are required' }, 400);
  }

  const passwordHash = await hashPassword(body.password);

  try {
    await c.env.DB.prepare(
      `INSERT INTO users (id, email, password_hash, full_name, tenant_id, role, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), 1)`
    ).bind(body.id, body.email, passwordHash, body.full_name, body.tenant_id, body.role).run();

    return c.json({ message: 'User created', id: body.id }, 201);
  } catch (err: any) {
    if (err.message?.includes('UNIQUE')) {
      return c.json({ error: 'Conflict', message: 'Email already exists' }, 409);
    }
    throw err;
  }
});

// ─── Password Hashing Helpers (PBKDF2 via Web Crypto) ─────
async function hashPassword(password: string): Promise<string> {
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

async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [saltHex, storedHashHex] = stored.split(':');
  const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map(h => parseInt(h, 16)));
  const encoder = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']
  );
  const derivedBits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    keyMaterial, 256
  );
  const hash = new Uint8Array(derivedBits);
  const hashHex = Array.from(hash).map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex === storedHashHex;
}
