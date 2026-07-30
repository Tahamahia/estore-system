import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const toolRoutes = new Hono<AppEnv>();

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

// ─── SSRF guard — only the USER-SUPPLIED input is checked ──
// Intermediate redirect hops may pass through CDN/deeplink services
// (e.g. AppsFlyer for onelink.shein.com), so we only block clearly
// non-Shein starting URLs rather than every hop in the chain.
const SHEIN_INPUT_PATTERN = /^https?:\/\/([a-z0-9-]+\.)*shein\.(com|top|co\.uk|com\.au|de|fr|es|it|se|nl|be|at|ch|pl|ru|br|mx|in|jp|kr|com\.ar|com\.br|com\.mx)([/?#]|$)/i;

function isSheinUrl(urlStr: string): boolean {
  // Also allow sheinlinks.com (Shein's own link shortener)
  if (/^https?:\/\/([a-z0-9-]+\.)*sheinlinks\.com([/?#]|$)/i.test(urlStr)) return true;
  return SHEIN_INPUT_PATTERN.test(urlStr);
}

/** Extract the `shc` share-cart code from a URL string. */
function extractShcFromUrl(url: string): string | null {
  try {
    // Standard query param
    const shc = new URL(url).searchParams.get('shc');
    if (shc && /^[A-Za-z0-9_-]{3,60}$/.test(shc)) return shc;
  } catch { /* fall through */ }
  // Regex fallback covers hashes and malformed URLs
  const m = url.match(/[?&#]shc=([A-Za-z0-9_-]{3,60})/);
  return m ? m[1] : null;
}

/** Scan raw HTML/JSON response text for an embedded shc code. */
function extractShcFromBody(body: string): string | null {
  // JSON key: "shc":"XXXXX"
  const jsonMatch = body.match(/"shc"\s*:\s*"([A-Za-z0-9_-]{3,60})"/);
  if (jsonMatch) return jsonMatch[1];
  // URL param embedded in HTML: shc=XXXXX
  const paramMatch = body.match(/[?&#]shc=([A-Za-z0-9_-]{3,60})/);
  if (paramMatch) return paramMatch[1];
  // share-cart URL pattern anywhere in the page
  const urlMatch = body.match(/share[_-]?cart[^'"]*shc=([A-Za-z0-9_-]{3,60})/i);
  if (urlMatch) return urlMatch[1];
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

// ─── Route ────────────────────────────────────────────────

toolRoutes.post('/parse-shein-cart', async (c) => {
  let body: { url?: string };
  try {
    body = await c.req.json<{ url?: string }>();
  } catch {
    return c.json({ error: 'يجب أن يحتوي الطلب على JSON مع حقل "url"' }, 400);
  }

  const rawUrl = (body?.url ?? '').trim();
  if (!rawUrl) return c.json({ error: 'حقل "url" مطلوب' }, 400);

  if (!isSheinUrl(rawUrl)) {
    return c.json({ error: 'يجب أن يكون الرابط من موقع شي إن (shein.com, shein.top, إلخ)' }, 400);
  }

  // ── Step 1: follow all redirects with native CF runtime ──────────────
  // redirect:'follow' lets the runtime traverse the full chain (including
  // through AppsFlyer/onelink CDN hops) without us needing to check each
  // intermediate domain.  We only validated the *input* URL above.
  let landingResp: Response;
  let landingBody = '';
  try {
    landingResp = await fetch(rawUrl, {
      redirect: 'follow',
      headers: {
        'User-Agent':     MOBILE_UA,
        'Accept':         'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language':'en-US,en;q=0.9,ar;q=0.8',
      },
    });
    // Read body for HTML-based shc extraction (capped at 256 KB)
    const buf = await landingResp.arrayBuffer();
    landingBody = new TextDecoder().decode(buf.slice(0, 262144));
  } catch (err) {
    return c.json({ error: `فشل تتبع الرابط: ${err instanceof Error ? err.message : err}` }, 502);
  }

  // ── Step 2: extract shc from final URL or page body ──────────────────
  const finalUrl = landingResp.url || rawUrl;
  let shc = extractShcFromUrl(finalUrl) ?? extractShcFromBody(landingBody);

  // Fallback: for shein.top/XXXXX the path segment itself is the share code
  if (!shc) {
    try {
      const pathPart = new URL(rawUrl).pathname.replace(/^\/+/, '').split('/')[0];
      if (pathPart && /^[A-Za-z0-9_-]{4,30}$/.test(pathPart)) {
        shc = pathPart;
      }
    } catch { /* ignore */ }
  }

  if (!shc) {
    return c.json({
      error: 'تعذر استخراج رمز السلة من الرابط. تأكد أن هذا رابط سلة مشتركة من شي إن وليس رابط منتج عادي.',
      resolved_url: finalUrl,
    }, 422);
  }

  // ── Step 3: call Shein's internal share-cart API ──────────────────────
  const apiUrl = `https://m.shein.com/api/cart/share/detail?shc=${encodeURIComponent(shc)}`;
  let apiData: Record<string, unknown>;
  try {
    const apiResp = await fetch(apiUrl, {
      headers: {
        'User-Agent':        MOBILE_UA,
        'Accept':            'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With':  'XMLHttpRequest',
        'Referer':           'https://m.shein.com/',
        'Accept-Language':   'en-US,en;q=0.9,ar;q=0.8',
      },
    });

    const raw = await apiResp.text();

    // Shein sometimes returns 200 with an error payload ({code: -1, ...})
    // or a non-JSON page when WAF triggers. Handle both gracefully.
    try {
      apiData = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return c.json({
        error: 'لم يتمكن الخادم من قراءة رد شي إن. قد يكون الرابط قد انتهت صلاحيته.',
        http_status: apiResp.status,
      }, 502);
    }

    // Shein uses code:0 for success; anything else is an API-level error
    const code = apiData.code ?? apiData.status;
    if (code !== 0 && code !== '0' && !apiResp.ok) {
      const msg = String(apiData.msg || apiData.message || apiData.error || '');
      return c.json({
        error: `رفض موقع شي إن الطلب${msg ? `: ${msg}` : ''}. حاول فتح الرابط في المتصفح للتأكد من صلاحيته.`,
        shein_code: code,
      }, 400);
    }
  } catch (err) {
    return c.json({ error: `فشل الاتصال بخادم شي إن: ${err instanceof Error ? err.message : err}` }, 502);
  }

  // ── Step 4: map response items ────────────────────────────────────────
  const items = hunt(apiData);
  if (!items.length) {
    return c.json({
      error: 'السلة فارغة أو انتهت صلاحية الرابط. تأكد أن الرابط لا يزال صالحاً.',
      shc,
    }, 422);
  }

  return c.json({ items });
});
