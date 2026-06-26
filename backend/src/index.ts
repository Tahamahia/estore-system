import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { authMiddleware } from './middleware/auth';
import { tenantMiddleware } from './middleware/tenant';
import { idempotencyMiddleware } from './middleware/idempotency';
import { authRoutes } from './routes/auth';
import { orderRoutes } from './routes/orders';
import { shipmentRoutes } from './routes/shipments';
import { warehouseRoutes } from './routes/warehouse';
import { customerRoutes } from './routes/customers';
import { inventoryRoutes } from './routes/inventory';
import { analyticsRoutes } from './routes/analytics';
import { webhookRoutes } from './routes/webhooks';
import { cronHandler } from './cron';
import type { AppEnv } from './types';

export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;
  CACHE: KVNamespace;
  JWT_SECRET: string;
  JWT_ISSUER: string;
  ENVIRONMENT: string;
  TELEGRAM_BOT_TOKEN?: string;
  SENTRY_DSN?: string;
}

const app = new Hono<AppEnv>();

// ─── Global Middleware ─────────────────────────────────────
app.use('*', logger());
app.use('*', cors({
  origin: '*',
  allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Tenant-ID'],
  maxAge: 86400,
}));

// ─── Health Check ──────────────────────────────────────────
app.get('/health', (c) => c.json({ 
  status: 'ok', 
  version: '1.0.0',
  timestamp: new Date().toISOString() 
}));

// ─── Public Routes ─────────────────────────────────────────
app.route('/api/v1/auth', authRoutes);
app.route('/api/v1/webhooks', webhookRoutes);

// ─── Protected Routes (Auth + Tenant Isolation) ────────────
const protectedApp = new Hono<AppEnv>();
protectedApp.use('*', authMiddleware);
protectedApp.use('*', tenantMiddleware);
protectedApp.use('*', idempotencyMiddleware);

protectedApp.route('/orders', orderRoutes);
protectedApp.route('/shipments', shipmentRoutes);
protectedApp.route('/warehouse', warehouseRoutes);
protectedApp.route('/customers', customerRoutes);
protectedApp.route('/inventory', inventoryRoutes);
protectedApp.route('/analytics', analyticsRoutes);

app.route('/api/v1', protectedApp);

// ─── 404 Handler ───────────────────────────────────────────
app.notFound((c) => c.json({ error: 'Not Found', path: c.req.path }, 404));

// ─── Error Handler ─────────────────────────────────────────
app.onError((err, c) => {
  console.error(`[ERROR] ${err.message}`, err.stack);
  return c.json({ 
    error: 'Internal Server Error', 
    message: c.env.ENVIRONMENT === 'development' ? err.message : undefined 
  }, 500);
});

export default {
  fetch: app.fetch,
  scheduled: cronHandler,
};
