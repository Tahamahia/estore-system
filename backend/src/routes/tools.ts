import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const toolRoutes = new Hono<AppEnv>();

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

const ALLOWED_SHEIN_HOSTS = [
  'shein.com',
  'shein.top',
  'sheinlinks.com',
  'm.shein.com',
  'onelink.shein.com',
  'in.shein.com',
  'us.shein.com',
  'ar.shein.com',
  'fr.shein.com',
  'de.shein.com',
  'uk.shein.com',
  'eu.shein.com',
];

function isSheinHost(urlStr: string): boolean {
  try {
    const host = new URL(urlStr).hostname.toLowerCase();
    return ALLOWED_SHEIN_HOSTS.some((d) => host === d || host.endsWith('.' + d));
  } catch {
    return false;
  }
}

/** Follow HTTP 3xx redirects manually to stay in allowed-host list. */
async function resolveRedirects(start: string, maxHops = 8): Promise<string> {
  let current = start;
  for (let i = 0; i < maxHops; i++) {
    if (!isSheinHost(current)) {
      throw new Error(`Redirect left Shein domain: ${current}`);
    }
    const resp = await fetch(current, {
      method: 'GET',
      redirect: 'manual',
      headers: { 'User-Agent': MOBILE_UA, Accept: 'text/html,*/*;q=0.8' },
    });
    if (resp.status < 300 || resp.status >= 400) return current;
    const loc = resp.headers.get('location');
    if (!loc) return current;
    current = loc.startsWith('http') ? loc : new URL(loc, current).href;
  }
  return current;
}

/** Extract the `shc` share-cart code from a URL string. */
function extractShc(url: string): string | null {
  try {
    const shc = new URL(url).searchParams.get('shc');
    if (shc) return shc;
  } catch { /* fall through */ }
  const m = url.match(/[?&#]shc=([A-Za-z0-9_-]+)/);
  return m ? m[1] : null;
}

// ─── Field mapping helpers ─────────────────────────────────

function toPrice(v: unknown): number {
  if (!v) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return parseFloat(v) || 0;
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if (o.amount)    return parseFloat(o.amount as string)    || 0;
    if (o.usdAmount) return parseFloat(o.usdAmount as string) || 0;
  }
  return 0;
}

function getAttrs(list: unknown): { size: string; color: string } {
  let size = '', color = '';
  if (!Array.isArray(list)) return { size, color };
  for (const a of list) {
    const attr = a as Record<string, unknown>;
    const n = String(attr.attr_name || attr.name || '').toLowerCase();
    const v = String(attr.attr_value_name || attr.attr_value || attr.value || '');
    if (n.includes('size'))                            size  = v;
    if (n.includes('color') || n.includes('colour'))  color = v;
  }
  return { size, color };
}

function buildUrl(g: Record<string, unknown>): string {
  const slug = g.goods_url_name || g.goodsUrlName || '';
  const id   = g.goods_id || '';
  if (slug && id) return `https://www.shein.com/p-${slug}-p-${id}.html`;
  const sn = g.goods_sn || g.goodsSn || '';
  if (sn) return `https://www.shein.com/brand-p-${sn}.html`;
  return '';
}

function mapItem(g: Record<string, unknown>): Record<string, unknown> | null {
  const name = String(g.goods_name || g.product_name || g.name || '');
  if (!name) return null;
  const attrs = getAttrs(g.attr_value_list || g.attrValueList || g.skc_sale_attr);
  return {
    name,
    url:   buildUrl(g),
    sku:   String(g.goods_sn || g.goodsSn || g.sku || ''),
    price: toPrice(g.salePrice || g.sale_price || g.unitPrice || g.price),
    qty:   Math.max(1, parseInt(String(g.quantity || g.buy_num || 1), 10) || 1),
    size:  attrs.size,
    color: attrs.color,
  };
}

/** Recursively search for a goods array inside an arbitrary JSON tree. */
function hunt(obj: unknown, depth = 0): Record<string, unknown>[] {
  if (depth > 8 || !obj || typeof obj !== 'object') return [];

  if (Array.isArray(obj)) {
    const arr = obj as unknown[];
    if (arr.length > 0) {
      const first = arr[0] as Record<string, unknown>;
      if (first?.goods_name) {
        const out: Record<string, unknown>[] = [];
        for (const g of arr) {
          const item = mapItem(g as Record<string, unknown>);
          if (item) out.push(item);
        }
        if (out.length) return out;
      }
    }
    for (let i = 0; i < Math.min(arr.length, 30); i++) {
      const f = hunt(arr[i], depth + 1);
      if (f.length) return f;
    }
    return [];
  }

  const rec = obj as Record<string, unknown>;
  for (const key of ['carts', 'cartList', 'cart_list', 'goods_list', 'goodsList', 'products', 'items', 'result']) {
    if (rec[key]) {
      const r = hunt(rec[key], depth + 1);
      if (r.length) return r;
    }
  }
  for (const key of Object.keys(rec).slice(0, 50)) {
    const q = hunt(rec[key], depth + 1);
    if (q.length) return q;
  }
  return [];
}

// ─── Route ────────────────────────────────────────────────

toolRoutes.post('/parse-shein-cart', async (c) => {
  let body: { url?: string };
  try {
    body = await c.req.json<{ url?: string }>();
  } catch {
    return c.json({ error: 'Request body must be JSON with a "url" field' }, 400);
  }

  const rawUrl = (body?.url ?? '').trim();
  if (!rawUrl) return c.json({ error: '"url" is required' }, 400);

  if (!isSheinHost(rawUrl)) {
    return c.json({ error: 'URL must be a Shein link (shein.com, shein.top, etc.)' }, 400);
  }

  // Step 1 — follow redirects (shortlinks → canonical URL)
  let finalUrl: string;
  try {
    finalUrl = await resolveRedirects(rawUrl);
  } catch (err) {
    return c.json({ error: `Redirect error: ${err instanceof Error ? err.message : err}` }, 502);
  }

  // Step 2 — extract share code
  const shc = extractShc(finalUrl);
  if (!shc) {
    return c.json({
      error: 'Could not extract share code (shc=…) from URL. Make sure this is a Shein shared-cart link.',
      resolved_url: finalUrl,
    }, 422);
  }

  // Step 3 — call Shein's internal share-cart API
  const apiUrl = `https://m.shein.com/api/cart/share/detail?shc=${encodeURIComponent(shc)}`;
  let apiData: Record<string, unknown>;
  try {
    const resp = await fetch(apiUrl, {
      headers: {
        'User-Agent':       MOBILE_UA,
        'Accept':           'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer':          'https://m.shein.com/',
        'Accept-Language':  'en-US,en;q=0.9,ar;q=0.8',
      },
    });
    if (!resp.ok) {
      return c.json({ error: `Shein API returned HTTP ${resp.status}` }, 502);
    }
    apiData = (await resp.json()) as Record<string, unknown>;
  } catch (err) {
    return c.json({ error: `Shein API request failed: ${err instanceof Error ? err.message : err}` }, 502);
  }

  // Step 4 — extract and map cart items
  const items = hunt(apiData);
  if (!items.length) {
    return c.json({
      error: 'No cart items found in Shein response. The link may have expired or the cart is empty.',
      shc,
    }, 422);
  }

  return c.json({ items });
});
