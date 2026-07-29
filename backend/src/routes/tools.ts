import { Hono } from 'hono';
import type { AppEnv } from '../types';

export const toolRoutes = new Hono<AppEnv>();

interface ParsedItem {
  name: string;
  price: number;
  qty: number;
  size: string;
  color: string;
  sku: string;
  product_url: string;
}

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

function safeJson(s: string): any {
  try { return JSON.parse(s); } catch { return null; }
}

/**
 * Bracket-balanced JSON extractor starting at `startIdx`.
 * Caps at maxLen to avoid runaway parsing on huge SSR payloads.
 */
function extractJsonAt(html: string, startIdx: number, maxLen = 700_000): any {
  const open  = html[startIdx];
  const close = open === '{' ? '}' : open === '[' ? ']' : null;
  if (!close) return null;
  let depth = 0, inStr = false, esc = false;
  const limit = Math.min(startIdx + maxLen, html.length);
  for (let i = startIdx; i < limit; i++) {
    const c = html[i];
    if (esc)                    { esc = false; continue; }
    if (c === '\\' && inStr)    { esc = true;  continue; }
    if (c === '"')              { inStr = !inStr; continue; }
    if (inStr)                  continue;
    if (c === '{' || c === '[') { depth++; continue; }
    if (c === '}' || c === ']') {
      if (--depth === 0) return safeJson(html.slice(startIdx, i + 1));
    }
  }
  return null;
}

function findJson(html: string, marker: string): any {
  let pos = html.indexOf(marker);
  if (pos === -1) return null;
  pos += marker.length;
  while (pos < html.length && ' \t\n\r=;'.includes(html[pos])) pos++;
  return extractJsonAt(html, pos);
}

function toFloat(v: any): number {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return parseFloat(v) || 0;
  if (v.amount)    return parseFloat(v.amount)    || 0;
  if (v.usdAmount) return parseFloat(v.usdAmount) || 0;
  return 0;
}

function parseAttrs(list: any[]): { size: string; color: string } {
  let size = '', color = '';
  if (!Array.isArray(list)) return { size, color };
  for (const a of list) {
    const n = String(a?.attr_name ?? a?.name ?? '').toLowerCase();
    const v = String(a?.attr_value_name ?? a?.attr_value ?? a?.value ?? '');
    if (n.includes('size'))                                             size  = v;
    if (n.includes('color') || n.includes('colour') || n === 'color') color = v;
  }
  return { size, color };
}

function buildSheinUrl(g: any): string {
  const slug = String(g?.goods_url_name ?? g?.goodsUrlName ?? '');
  const id   = g?.goods_id ?? '';
  if (slug && id) return `https://www.shein.com/p-${slug.replace(/\s+/g, '-')}-p-${id}.html`;
  const sn = String(g?.goods_sn ?? g?.goodsSn ?? '');
  if (sn) return `https://www.shein.com/brand-p-${sn}.html`;
  return String(g?.product_url ?? '');
}

function goodsToItem(g: any): ParsedItem | null {
  const name = String(g?.goods_name ?? g?.product_name ?? g?.name ?? '').trim();
  if (!name) return null;
  const { size, color } = parseAttrs(
    g?.attr_value_list ?? g?.attrValueList ?? g?.skc_sale_attr ?? []
  );
  return {
    name,
    price: toFloat(g?.salePrice ?? g?.sale_price ?? g?.unitPrice ?? g?.price),
    qty:   Math.max(1, parseInt(String(g?.quantity ?? g?.buy_num ?? 1), 10) || 1),
    size,
    color,
    sku:         String(g?.goods_sn ?? g?.goodsSn ?? g?.sku ?? ''),
    product_url: buildSheinUrl(g),
  };
}

/** Recursively hunt for arrays whose first element has a `goods_name` field. */
function huntCart(obj: any, depth = 0): ParsedItem[] {
  if (depth > 8 || !obj || typeof obj !== 'object') return [];

  if (Array.isArray(obj)) {
    if (obj.length > 0 && (obj[0]?.goods_name || obj[0]?.product_name)) {
      const out = obj.map(goodsToItem).filter(Boolean) as ParsedItem[];
      if (out.length) return out;
    }
    for (const el of obj.slice(0, 30)) {
      const found = huntCart(el, depth + 1);
      if (found.length) return found;
    }
    return [];
  }

  // Probe high-probability keys first
  for (const k of ['carts', 'cartList', 'cart_list', 'goods_list', 'goodsList', 'products', 'items', 'result']) {
    if (obj[k]) {
      const found = huntCart(obj[k], depth + 1);
      if (found.length) return found;
    }
  }
  // Breadth scan on remaining keys
  for (const k of Object.keys(obj).slice(0, 50)) {
    const found = huntCart(obj[k], depth + 1);
    if (found.length) return found;
  }
  return [];
}

function ogFallback(html: string, pageUrl: string): ParsedItem | null {
  const get = (prop: string) => {
    const m =
      html.match(new RegExp(`<meta[^>]*property=["']${prop}["'][^>]*content=["']([^"']+)["']`, 'i')) ??
      html.match(new RegExp(`<meta[^>]*content=["']([^"']+)["'][^>]*property=["']${prop}["']`, 'i'));
    return m?.[1] ?? '';
  };
  const name = get('og:title').replace(/\s*[|–-]\s*SHEIN.*/i, '').trim();
  if (!name) return null;
  const price   = parseFloat(get('product:price:amount') || get('og:price:amount') || '0') || 0;
  const url     = get('og:url') || pageUrl;
  const snMatch = url.match(/\bp-([A-Z0-9]{6,})\b/i);
  return { name, price, qty: 1, size: '', color: '', sku: snMatch?.[1] ?? '', product_url: url };
}

// ─── POST /tools/parse-shein-cart ─────────────────────────────────
toolRoutes.post('/parse-shein-cart', async (c) => {
  const body = await c.req.json<{ url?: string }>();
  const rawUrl = (body?.url ?? '').trim();
  if (!rawUrl) return c.json({ error: 'url is required' }, 400);

  let parsed: URL;
  try { parsed = new URL(rawUrl); }
  catch { return c.json({ error: 'Invalid URL' }, 400); }

  const host = parsed.hostname.replace(/^www\./, '');
  const allowed = ['shein.com', 'shein.top', 'shein.co.uk', 'shein.eu', 'shein.com.mx'];
  if (!allowed.some(h => host === h || host.endsWith('.' + h))) {
    return c.json({ error: 'URL must be a Shein domain (shein.com, shein.top, …)' }, 400);
  }

  let html: string;
  let finalUrl: string;

  try {
    const res = await fetch(rawUrl, {
      method: 'GET',
      redirect: 'follow',
      headers: {
        'User-Agent':              MOBILE_UA,
        'Accept':                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language':         'en-US,en;q=0.9',
        'Cache-Control':           'max-age=0',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest':          'document',
        'Sec-Fetch-Mode':          'navigate',
        'Sec-Fetch-Site':          'none',
        'Sec-Fetch-User':          '?1',
      },
    });
    finalUrl = res.url;
    if (!res.ok) {
      return c.json({ items: [], partial: true, strategy: 'fetch_error', error: `HTTP ${res.status}` });
    }
    html = await res.text();
  } catch (e) {
    return c.json({ items: [], partial: true, strategy: 'network_error', error: String(e) });
  }

  // ── Strategy 1: __PRELOADED_STATE__ ────────────────────────────
  {
    const state = findJson(html, '__PRELOADED_STATE__');
    if (state) {
      const items = huntCart(state);
      if (items.length) return c.json({ items, partial: false, strategy: 'preloaded_state' });
    }
  }

  // ── Strategy 2: gbCartData ──────────────────────────────────────
  {
    const cart = findJson(html, 'gbCartData');
    if (cart) {
      const items = huntCart(cart);
      if (items.length) return c.json({ items, partial: false, strategy: 'cart_data' });
    }
  }

  // ── Strategy 3: JSON-LD Product schema ─────────────────────────
  {
    const rx = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
    let m: RegExpExecArray | null;
    while ((m = rx.exec(html)) !== null) {
      const ld = safeJson(m[1]);
      if (!ld) continue;
      const entries: any[] = Array.isArray(ld) ? ld : [ld];
      const products = entries.filter((e: any) => e?.['@type'] === 'Product');
      if (products.length) {
        return c.json({
          items: products.map((p: any): ParsedItem => ({
            name:        String(p.name ?? ''),
            price:       parseFloat(String(p?.offers?.price ?? p?.offers?.[0]?.price ?? 0)) || 0,
            qty:         1,
            size:        '',
            color:       '',
            sku:         String(p.sku ?? p.mpn ?? ''),
            product_url: String(p?.offers?.url ?? p.url ?? finalUrl),
          })),
          partial: false,
          strategy: 'json_ld',
        });
      }
    }
  }

  // ── Strategy 4: OpenGraph fallback (single product) ────────────
  {
    const item = ogFallback(html, finalUrl);
    if (item?.name) {
      return c.json({ items: [item], partial: true, strategy: 'opengraph' });
    }
  }

  return c.json({
    items:    [],
    partial:  true,
    strategy: 'none',
    error:    'Could not extract product data — page may require JavaScript rendering or is bot-protected',
  });
});
