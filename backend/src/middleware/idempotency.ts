import { Context, Next } from 'hono';
import type { AppEnv } from '../types';

export const idempotencyMiddleware = async (c: Context<AppEnv>, next: Next) => {
  const method = c.req.method;
  if (!['POST', 'PUT', 'PATCH'].includes(method)) {
    return next();
  }

  const idempotencyKey = c.req.header('Idempotency-Key');
  if (!idempotencyKey) {
    return c.json({ error: 'Bad Request', message: 'Idempotency-Key header is required for mutation requests' }, 400);
  }

  const tenantId = c.get('tenant_id') || 'global';
  const cacheKey = `idempotency:${tenantId}:${idempotencyKey}`;

  try {
    const cached = await c.env.CACHE.get(cacheKey, 'json');
    if (cached) {
      const cachedResponse = cached as { status: number; body: unknown };
      return c.json(
        { ...cachedResponse.body as object, _idempotent: true },
        cachedResponse.status as 200
      );
    }

    await next();

    const responseBody = await c.res.clone().json().catch(() => null);
    if (responseBody) {
      await c.env.CACHE.put(
        cacheKey,
        JSON.stringify({ status: c.res.status, body: responseBody }),
        { expirationTtl: 86400 }
      );
    }
  } catch (err) {
    console.error('[IDEMPOTENCY] Cache error:', err);
    await next();
  }
};
