import { Context, Next } from 'hono';
import type { AppEnv } from '../types';

export const tenantMiddleware = async (c: Context<AppEnv>, next: Next) => {
  const user = c.get('user');
  if (!user) {
    return c.json({ error: 'Unauthorized', message: 'User context missing' }, 401);
  }

  let tenantId = user.tenant_id;

  if (user.role === 'super_admin') {
    const overrideTenant = c.req.header('X-Tenant-ID');
    if (overrideTenant) tenantId = overrideTenant;
  }

  if (!tenantId) {
    return c.json({ error: 'Forbidden', message: 'No tenant context available' }, 403);
  }

  c.set('tenant_id', tenantId);
  c.set('user_id', user.sub);
  c.set('user_role', user.role);

  await next();
};

export function requireRole(...allowedRoles: string[]) {
  return async (c: Context<AppEnv>, next: Next) => {
    const role = c.get('user_role');
    if (!role || !allowedRoles.includes(role)) {
      return c.json({ error: 'Forbidden', message: `Insufficient permissions` }, 403);
    }
    await next();
  };
}
