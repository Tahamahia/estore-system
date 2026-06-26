import type { Env } from './index';

// Cron Trigger Handler
// Runs on scheduled triggers defined in wrangler.toml:
//   - "0 3 * * *"    → Daily DB backup to R2
//   - "0 every-6h"   → Zombie order cleanup every 6 hours
export const cronHandler = async (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => {
  const hour = new Date(event.scheduledTime).getUTCHours();

  if (hour === 3) {
    ctx.waitUntil(backupDatabase(env));
  }

  ctx.waitUntil(cleanupZombieOrders(env));
};

async function backupDatabase(env: Env): Promise<void> {
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const tables = ['tenants', 'users', 'customers', 'orders', 'order_items', 'shipments', 'master_shipments'];
    let backup = '';

    for (const table of tables) {
      const result = await env.DB.prepare(`SELECT * FROM ${table} WHERE is_deleted = 0`).all();
      backup += `-- TABLE: ${table}\n${JSON.stringify(result.results)}\n\n`;
    }

    await env.MEDIA.put(`backups/db-${timestamp}.json`, backup, {
      httpMetadata: { contentType: 'application/json' },
    });
    console.log(`[CRON] Database backup completed: db-${timestamp}.json`);
  } catch (err) {
    console.error('[CRON] Backup failed:', err);
  }
}

async function cleanupZombieOrders(env: Env): Promise<void> {
  try {
    // Auto-cancel orders pending payment for > 72 hours
    const cancelled = await env.DB.prepare(
      `UPDATE orders SET status = 'auto_cancelled', updated_at = datetime('now')
       WHERE status = 'pending_payment' AND is_deleted = 0
       AND created_at < datetime('now', '-72 hours')`
    ).run();
    console.log(`[CRON] Auto-cancelled ${cancelled.meta.changes} zombie orders`);

    // Flag orders pending 48-72 hours for reminder
    const reminders = await env.DB.prepare(
      `SELECT id, customer_id, tenant_id FROM orders
       WHERE status = 'pending_payment' AND is_deleted = 0
       AND created_at < datetime('now', '-48 hours')
       AND created_at >= datetime('now', '-72 hours')`
    ).all();

    if (reminders.results?.length) {
      console.log(`[CRON] ${reminders.results.length} orders need payment reminders`);
      // Future: trigger WhatsApp webhook here
    }
  } catch (err) {
    console.error('[CRON] Zombie cleanup failed:', err);
  }
}
