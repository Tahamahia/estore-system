import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const toolRoutes = new Hono<AppEnv>();

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

// ─── SSRF guard (input URL only) ──────────────────────────
// Intermediate redirect hops may pass through AppsFlyer/CDN domains —
// we only validate the user-supplied starting URL.
function isSheinUrl(urlStr: string): boolean {
  try {
    const host = new URL(urlStr).hostname.toLowerCase();
    // Accept *.shein.com, *.shein.top, sheinlinks.com, etc.
    return /^([a-z0-9-]+\.)*shein\.(com|top|co\.uk|com\.au|de|fr|es|it|se|nl|be|at|ch|pl|ru|in|jp|kr)$/.test(host)
      || /^([a-z0-9-]+\.)*sheinlinks\.com$/.test(host);
  } catch {
    return false;
  }
}

// ─── shc extraction helpers ───────────────────────────────

function extractShcFromUrl(url: string): string | null {
  try {
    const shc = new URL(url).searchParams.get('shc');
    if (shc && /^[A-Za-z0-9_-]{3,60}$/.test(shc)) return shc;
  } catch { /* fall through */ }
  const m = url.match(/[?&#]shc=([A-Za-z0-9_-]{3,60})/);
  return m ? m[1] : null;
}

/**
 * Walk the redirect chain ONE HOP AT A TIME using redirect:'manual'.
 * We inspect only the Location header at each hop — no body is consumed —
 * so we never trigger the WAF rule that fires when scrapers download full pages.
 * As soon as any Location header contains shc=, we return immediately.
 */
async function extractShcViaHops(startUrl: string): Promise<string | null> {
  // Fast path: shc already embedded in the input URL
  const direct = extractShcFromUrl(startUrl);
  if (direct) return direct;

  let current = startUrl;

  for (let hop = 0; hop < 5; hop++) {
    let resp: Response;
    try {
      resp = await fetch(current, {
        method: 'GET',
        redirect: 'manual',
        headers: {
          'User-Agent':      MOBILE_UA,
          'Accept':          'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8',
          'Cache-Control':   'no-cache',
        },
      });
    } catch {
      break; // network error — stop and fall through to path fallback
    }

    // Non-redirect response: end of chain without finding shc
    if (resp.status < 300 || resp.status >= 400) break;

    const location = resp.headers.get('location');
    if (!location) break;

    let resolved: string;
    try {
      resolved = location.startsWith('http') ? location : new URL(location, current).href;
    } catch {
      break;
    }

    // Location already contains shc= — extract it and stop; no further fetch needed
    const shcFromLocation = extractShcFromUrl(resolved);
    if (shcFromLocation) return shcFromLocation;

    current = resolved;
  }

  // Last-resort: for shein.top/XXXXX the path segment itself may be the share code
  try {
    const pathPart = new URL(startUrl).pathname.replace(/^\/+/, '').split('/')[0];
    if (pathPart && /^[A-Za-z0-9_-]{4,30}$/.test(pathPart)) return pathPart;
  } catch { /* ignore */ }

  return null;
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
    if (n.includes('size'))                           size  = v;
    if (n.includes('color') || n.includes('colour')) color = v;
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

function hunt(obj: unknown, depth = 0): Record<string, unknown>[] {
  if (depth > 8 || !obj || typeof obj !== 'object') return [];
  if (Array.isArray(obj)) {
    const arr = obj as unknown[];
    if (arr.length > 0 && (arr[0] as Record<string, unknown>)?.goods_name) {
      const out: Record<string, unknown>[] = [];
      for (const g of arr) {
        const item = mapItem(g as Record<string, unknown>);
        if (item) out.push(item);
      }
      if (out.length) return out;
    }
    for (let i = 0; i < Math.min(arr.length, 30); i++) {
      const f = hunt(arr[i], depth + 1);
      if (f.length) return f;
    }
    return [];
  }
  const rec = obj as Record<string, unknown>;
  for (const key of ['carts', 'cartList', 'cart_list', 'goods_list', 'goodsList', 'products', 'items', 'result', 'info', 'data']) {
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

// ─── Route — ALWAYS returns HTTP 200 ──────────────────────
// Dio crashes on 4xx/5xx. Every error path returns 200 with
// { success: false, message: "..." } so Flutter can handle it gracefully.

toolRoutes.post('/parse-shein-cart', async (c) => {
  const ok   = (items: Record<string, unknown>[]) => c.json({ success: true,  items });
  const fail = (message: string)                   => c.json({ success: false, message });

  try {
    // ── Parse request body ──────────────────────────────────
    let body: { url?: string };
    try {
      body = await c.req.json<{ url?: string }>();
    } catch {
      return fail('يجب أن يحتوي الطلب على JSON مع حقل "url"');
    }

    const rawUrl = (body?.url ?? '').trim();
    if (!rawUrl) return fail('حقل "url" مطلوب');
    if (!isSheinUrl(rawUrl)) return fail('يجب أن يكون الرابط من موقع شي إن (shein.com, shein.top, إلخ)');

    // ── Step 1: trace redirects to get shc ─────────────────
    let shc: string | null;
    try {
      shc = await extractShcViaHops(rawUrl);
    } catch (err) {
      return fail(`فشل تتبع الرابط: ${err instanceof Error ? err.message : String(err)}`);
    }

    if (!shc) {
      return fail('تعذر استخراج رمز السلة من الرابط. تأكد أن هذا رابط سلة مشتركة وليس رابط منتج عادي.');
    }

    // ── Step 2: call Shein's internal share-cart API ────────
    const apiUrl = `https://m.shein.com/api/cart/share/detail?shc=${encodeURIComponent(shc)}`;
    let apiResp: Response;
    try {
      apiResp = await fetch(apiUrl, {
        headers: {
          'User-Agent':        MOBILE_UA,
          'Accept':            'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With':  'XMLHttpRequest',
          'Referer':           'https://m.shein.com/',
          'Accept-Language':   'en-US,en;q=0.9,ar;q=0.8',
        },
      });
    } catch (err) {
      return fail(`فشل الاتصال بخادم شي إن: ${err instanceof Error ? err.message : String(err)}`);
    }

    let apiData: Record<string, unknown>;
    try {
      apiData = (await apiResp.json()) as Record<string, unknown>;
    } catch {
      return fail('لم يتمكن الخادم من قراءة رد شي إن. قد يكون الرابط قد انتهت صلاحيته أو تم حظر الطلب.');
    }

    // Shein API: code:0 means success; anything else is an application error
    const code = apiData.code ?? apiData.status;
    if (code !== 0 && code !== '0') {
      const msg = String(apiData.msg || apiData.message || apiData.error || '');
      return fail(`رفض موقع شي إن الطلب${msg ? `: ${msg}` : ''}. تأكد أن الرابط لا يزال صالحاً.`);
    }

    // ── Step 3: map items ───────────────────────────────────
    const items = hunt(apiData);
    if (!items.length) {
      return fail('السلة فارغة أو انتهت صلاحية الرابط. تأكد أن الرابط لا يزال صالحاً.');
    }

    return ok(items);

  } catch (err) {
    // Top-level safety net — should never reach here under normal conditions
    return fail(`خطأ غير متوقع: ${err instanceof Error ? err.message : String(err)}`);
  }
});
