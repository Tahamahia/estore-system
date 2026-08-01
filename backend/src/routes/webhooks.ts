import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const webhookRoutes = new Hono<AppEnv>();

// Telegram Bot webhook — /status ORD-123
webhookRoutes.post('/telegram', async (c) => {
  // FIX 5: Verify Telegram webhook secret token
  // Telegram sends the secret_token in the X-Telegram-Bot-Api-Secret-Token header
  // when configured via setWebhook({ secret_token: ... })
  const secretToken = c.req.header('X-Telegram-Bot-Api-Secret-Token');
  const expectedToken = c.env.TELEGRAM_BOT_TOKEN
    ? c.env.TELEGRAM_BOT_TOKEN.substring(0, 32)  // Use first 32 chars of bot token as webhook secret
    : null;

  if (expectedToken && secretToken !== expectedToken) {
    return c.json({ error: 'Forbidden' }, 403);
  }

  const body = await c.req.json();
  const message = body?.message;
  if (!message?.text) return c.json({ ok: true });

  const text = message.text.trim();
  const chatId = message.chat.id;

  if (text.startsWith('/status ')) {
    const orderId = text.slice(8).trim();

    // FIX 5: Only return status and timestamps — no customer data, prices, or internal IDs
    const order = await c.env.DB.prepare(
      `SELECT status, created_at, updated_at FROM orders WHERE id = ? OR platform_order_id = ?`
    ).bind(orderId, orderId).first();

    // No tenant context in webhook — return generic confirmation to avoid cross-tenant data exposure
    const reply = order
      ? `📦 تم العثور على الطلبية. للتفاصيل، يرجى مراجعة لوحة التحكم.`
      : `❌ لم يتم العثور على الطلبية.`;

    if (c.env.TELEGRAM_BOT_TOKEN) {
      await fetch(`https://api.telegram.org/bot${c.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text: reply, parse_mode: 'HTML' }),
      });
    }
  }

  return c.json({ ok: true });
});
