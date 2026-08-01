import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { generateJWT, authMiddleware } from '../middleware/auth';
import { tenantMiddleware, requireRole } from '../middleware/tenant';

export const authRoutes = new Hono<AppEnv>();

// Allowed roles for user registration
const ALLOWED_ROLES = ['super_admin', 'store_manager', 'purchaser', 'sorter', 'driver'];

// Basic email format validation
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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

  if (!EMAIL_REGEX.test(email)) {
    return c.json({ error: 'Bad Request', message: 'Invalid email format' }, 400);
  }

  if (password.length < 8) {
    return c.json({ error: 'Bad Request', message: 'Password must be at least 8 characters' }, 400);
  }

  // Query user by email (parameterized — no SQL injection)
  const user = await c.env.DB.prepare(
    `SELECT id, email, password_hash, tenant_id, role, full_name, is_deleted, status, is_active
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

  // Block accounts that are not fully active
  if ((user.status as string) === 'pending') {
    return c.json({ error: 'Pending', message: 'حسابك قيد المراجعة. انتظر موافقة المدير.' }, 403);
  }
  if ((user.status as string) === 'rejected') {
    return c.json({ error: 'Rejected', message: 'تم رفض طلب انضمامك. تواصل مع المدير.' }, 403);
  }
  if ((user as any).is_active === 0) {
    return c.json({ error: 'Inactive', message: 'تم تعطيل هذا الحساب. تواصل مع المدير.' }, 403);
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
 * POST /api/v1/auth/register (Super Admin only)
 * Creates a new user account.
 * FIX 3: Protected with auth + tenant middleware + super_admin role check.
 */
authRoutes.post('/register', authMiddleware, tenantMiddleware, requireRole('super_admin'), async (c) => {
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

  if (!EMAIL_REGEX.test(body.email)) {
    return c.json({ error: 'Bad Request', message: 'Invalid email format' }, 400);
  }

  if (body.password.length < 8) {
    return c.json({ error: 'Bad Request', message: 'Password must be at least 8 characters' }, 400);
  }

  if (!body.full_name.trim()) {
    return c.json({ error: 'Bad Request', message: 'full_name must not be empty' }, 400);
  }

  if (!ALLOWED_ROLES.includes(body.role)) {
    return c.json({ error: 'Bad Request', message: `Invalid role. Allowed: ${ALLOWED_ROLES.join(', ')}` }, 400);
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

/**
 * POST /api/v1/auth/signup — public self-registration
 * Creates a pending user with role=sorter. Admin must approve before login is allowed.
 */
authRoutes.post('/signup', async (c) => {
  const body = await c.req.json<{ full_name: string; email: string; password: string }>();

  if (!body.full_name?.trim() || !body.email || !body.password) {
    return c.json({ error: 'Bad Request', message: 'الاسم والإيميل وكلمة المرور مطلوبة' }, 400);
  }
  if (!EMAIL_REGEX.test(body.email)) {
    return c.json({ error: 'Bad Request', message: 'صيغة الإيميل غير صحيحة' }, 400);
  }
  if (body.password.length < 8) {
    return c.json({ error: 'Bad Request', message: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل' }, 400);
  }

  const tenant = await c.env.DB.prepare(
    `SELECT id FROM tenants WHERE is_deleted = 0 LIMIT 1`
  ).first();
  if (!tenant) {
    return c.json({ error: 'Setup Error', message: 'لم يتم إعداد المتجر بعد' }, 500);
  }

  const hash = await hashPassword(body.password);
  const id = crypto.randomUUID();

  try {
    await c.env.DB.prepare(
      `INSERT INTO users (id, tenant_id, email, password_hash, full_name, role, status, is_active, created_at, updated_at, version)
       VALUES (?, ?, ?, ?, ?, 'sorter', 'pending', 0, datetime('now'), datetime('now'), 1)`
    ).bind(id, tenant.id, body.email.toLowerCase().trim(), hash, body.full_name.trim()).run();

    return c.json({ message: 'تم إرسال طلب الانضمام. انتظر موافقة المدير.' }, 201);
  } catch (err: any) {
    if (err.message?.includes('UNIQUE')) {
      return c.json({ error: 'Conflict', message: 'هذا الإيميل مسجّل مسبقاً' }, 409);
    }
    throw err;
  }
});

/**
 * PATCH /api/v1/auth/change-password (authenticated users)
 * Verifies current_password, then sets new_password.
 */
authRoutes.patch('/change-password', authMiddleware, tenantMiddleware, async (c) => {
  const userId = c.get('user_id') as string;
  const body = await c.req.json<{ current_password: string; new_password: string }>();

  if (!body.current_password || !body.new_password) {
    return c.json({ error: 'Bad Request', message: 'current_password و new_password مطلوبان' }, 400);
  }

  if (body.new_password.length < 8) {
    return c.json({ error: 'Bad Request', message: 'كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل' }, 400);
  }

  const user = await c.env.DB.prepare(
    `SELECT id, password_hash FROM users WHERE id = ? AND is_deleted = 0`
  ).bind(userId).first();

  if (!user) {
    return c.json({ error: 'Not Found', message: 'المستخدم غير موجود' }, 404);
  }

  const isValid = await verifyPassword(body.current_password, user.password_hash as string);
  if (!isValid) {
    return c.json({ error: 'Unauthorized', message: 'كلمة المرور الحالية غير صحيحة' }, 401);
  }

  const newHash = await hashPassword(body.new_password);
  await c.env.DB.prepare(
    `UPDATE users SET password_hash = ?, updated_at = datetime('now') WHERE id = ?`
  ).bind(newHash, userId).run();

  return c.json({ message: 'تم تغيير كلمة المرور بنجاح' });
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
