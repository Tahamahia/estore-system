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
import { imageRoutes } from './routes/images';
import { purchaseRoutes } from './routes/purchasing';
import { landedCostRoutes } from './routes/landed-cost';
import { walletRoutes } from './routes/wallets';
import { syncRoutes } from './routes/sync';
import { settlementRoutes } from './routes/settlements';
import { cronHandler } from './cron';
import { createSentryClient } from './lib/sentry';
import type { AppEnv } from './types';

export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;
  CACHE: KVNamespace;
  JWT_SECRET: string;
  JWT_ISSUER: string;
  ENVIRONMENT: string;
  FRONTEND_URL?: string;
  TELEGRAM_BOT_TOKEN?: string;
  SENTRY_DSN?: string;
}

const app = new Hono<AppEnv>();

// ─── Global Middleware ─────────────────────────────────────
app.use('*', logger());

// ─── Strict CORS ───────────────────────────────────────────
// Accepts the deployed Cloudflare Pages URL + localhost for dev
app.use('*', async (c, next) => {
  const frontendUrl = c.env.FRONTEND_URL || '';
  const allowedOrigins = [
    frontendUrl,
    'http://localhost:3000',
    'http://localhost:8080',
    'http://127.0.0.1:8080',
  ].filter(Boolean);

  const corsMiddleware = cors({
    origin: (origin) => {
      // FIX 7: Don't return wildcard for missing origin when credentials: true
      if (!origin) return '';
      // Check if origin matches any allowed origin (supports CF Pages preview URLs for estore-web only)
      if (allowedOrigins.some(allowed => origin === allowed) || origin.endsWith('.estore-web.pages.dev')) {
        return origin;
      }
      return '';  // Block
    },
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Tenant-ID'],
    exposeHeaders: ['X-Request-Id'],
    maxAge: 86400,
    credentials: true,
  });

  return corsMiddleware(c, next);
});

// ─── Sentry Error Tracking ────────────────────────────────
// Attaches Sentry client to every request context.
// Safe no-op if SENTRY_DSN is empty/null/missing.
app.use('*', async (c, next) => {
  const sentry = createSentryClient(c.req.raw, c.env);
  sentry.setTag('tenant_id', 'unknown');  // Will be overridden after auth

  try {
    await next();
  } catch (err) {
    sentry.captureException(err);
    throw err;  // Re-throw so the error handler below catches it
  }
});

// ─── Health Check ──────────────────────────────────────────
app.get('/health', (c) => c.json({
  status: 'ok',
  version: '2.0.0',
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
protectedApp.route('/images', imageRoutes);
protectedApp.route('/purchasing', purchaseRoutes);
protectedApp.route('/landed-cost', landedCostRoutes);
protectedApp.route('/wallets', walletRoutes);
protectedApp.route('/sync', syncRoutes);
protectedApp.route('/settlements', settlementRoutes);

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
