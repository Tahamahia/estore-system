import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const userRoutes = new Hono<AppEnv>();

const ALLOWED_ROLES = ['super_admin', 'store_manager', 'purchaser', 'sorter', 'driver'];

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

/**
 * GET /users — list all users for this tenant (super_admin only)
 * Never returns password_hash.
 */
userRoutes.get('/', requireRole('super_admin'), async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const result = await c.env.DB.prepare(
    `SELECT id, email, full_name, role, is_active, created_at
     FROM users
     WHERE tenant_id = ? AND is_deleted = 0
     ORDER BY created_at ASC`
  ).bind(tenantId).all();

  return c.json({ data: result.results });
});

/**
 * PATCH /users/:id — update role or is_active (super_admin only)
 */
userRoutes.patch('/:id', requireRole('super_admin'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const currentUserId = c.get('user_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json<{ role?: string; is_active?: number }>();

  if (body.is_active === 0 && id === currentUserId) {
    return c.json({ error: 'Bad Request', message: 'لا يمكنك تعطيل حسابك الخاص' }, 400);
  }

  if (body.role !== undefined && !ALLOWED_ROLES.includes(body.role)) {
    return c.json({ error: 'Bad Request', message: `الأدوار المتاحة: ${ALLOWED_ROLES.join(', ')}` }, 400);
  }

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];

  if (body.role !== undefined) {
    setClauses.push('role = ?');
    values.push(body.role);
  }
  if (body.is_active !== undefined) {
    setClauses.push('is_active = ?');
    values.push(body.is_active);
  }

  if (values.length === 0) {
    return c.json({ error: 'Bad Request', message: 'لا توجد حقول صالحة للتحديث' }, 400);
  }

  const result = await c.env.DB.prepare(
    `UPDATE users SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(...values, id, tenantId).run();

  if (result.meta.changes === 0) {
    return c.json({ error: 'Not Found', message: 'المستخدم غير موجود' }, 404);
  }

  return c.json({ message: 'تم التحديث', id });
});

/**
 * DELETE /users/:id — soft delete (super_admin only)
 */
userRoutes.delete('/:id', requireRole('super_admin'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const currentUserId = c.get('user_id') as string;
  const id = c.req.param('id');

  if (id === currentUserId) {
    return c.json({ error: 'Bad Request', message: 'لا يمكنك حذف حسابك الخاص' }, 400);
  }

  const result = await c.env.DB.prepare(
    `UPDATE users SET is_deleted = 1, deleted_by = ?, deleted_at = datetime('now'), updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(currentUserId, id, tenantId).run();

  if (result.meta.changes === 0) {
    return c.json({ error: 'Not Found', message: 'المستخدم غير موجود' }, 404);
  }

  return c.json({ message: 'تم حذف المستخدم', id });
});

/**
 * PATCH /users/:id/reset-password — set new password for any tenant user (super_admin only)
 */
userRoutes.patch('/:id/reset-password', requireRole('super_admin'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json<{ new_password: string }>();

  if (!body.new_password || body.new_password.length < 8) {
    return c.json({ error: 'Bad Request', message: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل' }, 400);
  }

  const hash = await hashPassword(body.new_password);

  const result = await c.env.DB.prepare(
    `UPDATE users SET password_hash = ?, updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
  ).bind(hash, id, tenantId).run();

  if (result.meta.changes === 0) {
    return c.json({ error: 'Not Found', message: 'المستخدم غير موجود' }, 404);
  }

  return c.json({ message: 'تم تغيير كلمة المرور' });
});
