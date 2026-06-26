import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const webhookRoutes = new Hono<AppEnv>();

// Telegram Bot webhook — /status ORD-123
webhookRoutes.post('/telegram', async (c) => {
  const body = await c.req.json();
  const message = body?.message;
  if (!message?.text) return c.json({ ok: true });

  const text = message.text.trim();
  const chatId = message.chat.id;

  if (text.startsWith('/status ')) {
    const orderId = text.slice(8).trim();
    const order = await c.env.DB.prepare(
      `SELECT id, status, platform, platform_order_id, created_at FROM orders WHERE id = ? OR platform_order_id = ?`
    ).bind(orderId, orderId).first();

    const reply = order
      ? `📦 Order ${order.id}\nStatus: ${order.status}\nPlatform: ${order.platform || 'N/A'}\nCreated: ${order.created_at}`
      : `❌ Order "${orderId}" not found.`;

    if (c.env.TELEGRAM_BOT_TOKEN) {
      await fetch(`https://api.telegram.org/bot${c.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text: reply, parse_mode: 'HTML' }),
      });
    }
  }

  return c.json({ ok: true });
});
