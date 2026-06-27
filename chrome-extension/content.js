/**
 * eStore Cart Extractor — Content Script
 * 
 * Multi-strategy extraction for Shein and Trendyol cart pages.
 * Strategies (tried in order):
 *   1. JSON-LD / __INITIAL_STATE__ / embedded JSON (most stable)
 *   2. Cart API interception via window.__cartData
 *   3. DOM traversal with fallback selectors
 *
 * SKU Identification:
 *   Shein SKUs follow patterns: numeric IDs (e.g., "sw2212345678901"),
 *   data-sku, goods_id, or the "SKC" identifier. The physical barcode
 *   on Shein bags matches the specific SKU (variant-level) ID.
 */

(() => {
  'use strict';

  // ─── Platform Detection ────────────────────────────────────
  const hostname = window.location.hostname;
  const isShein = hostname.includes('shein');
  const isTrendyol = hostname.includes('trendyol');

  /**
   * Master extraction function — dispatches to platform-specific logic
   */
  function extractCartItems() {
    try {
      if (isShein) return extractSheinCart();
      if (isTrendyol) return extractTrendyolCart();
      return { success: false, error: 'Unsupported platform', items: [] };
    } catch (err) {
      return { success: false, error: `Extraction failed: ${err.message}`, items: [] };
    }
  }

  // ─── SHEIN EXTRACTION ──────────────────────────────────────

  function extractSheinCart() {
    let items = [];

    // Strategy 1: Try embedded state/JSON data first (most reliable)
    items = extractSheinFromEmbeddedData();
    if (items.length > 0) {
      return { success: true, platform: 'shein', strategy: 'embedded_json', items };
    }

    // Strategy 2: DOM traversal (fallback)
    items = extractSheinFromDOM();
    if (items.length > 0) {
      return { success: true, platform: 'shein', strategy: 'dom_traversal', items };
    }

    return { success: false, error: 'Could not extract items. Make sure you are on the Shein cart page.', items: [] };
  }

  /**
   * Strategy 1: Extract from embedded JSON in page scripts
   * Shein often embeds cart data in window.__cart_data, gbCartSsrData, etc.
   */
  function extractSheinFromEmbeddedData() {
    const items = [];

    // Check for common Shein global state objects
    const stateKeys = [
      '__cart_data',
      'gbCartSsrData',
      '__INITIAL_STATE__',
      'gbCartInfo',
      '__NEXT_DATA__',
    ];

    for (const key of stateKeys) {
      try {
        const raw = window[key];
        if (!raw) continue;

        const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const cartItems = findCartItemsInObject(data);
        if (cartItems.length > 0) {
          for (const ci of cartItems) {
            items.push(normalizeSheinItem(ci));
          }
          return items;
        }
      } catch { /* continue to next key */ }
    }

    // Also check <script> tags with JSON-LD or embedded cart JSON
    const scripts = document.querySelectorAll('script[type="application/json"], script:not([src])');
    for (const script of scripts) {
      try {
        const text = script.textContent?.trim();
        if (!text || text.length < 50 || !text.includes('cart')) continue;
        const data = JSON.parse(text);
        const cartItems = findCartItemsInObject(data);
        if (cartItems.length > 0) {
          for (const ci of cartItems) {
            items.push(normalizeSheinItem(ci));
          }
          return items;
        }
      } catch { /* skip non-JSON scripts */ }
    }

    return items;
  }

  /**
   * Recursively search an object for arrays that look like cart item collections
   */
  function findCartItemsInObject(obj, depth = 0) {
    if (depth > 8 || !obj) return [];

    // Direct array of cart items
    if (Array.isArray(obj) && obj.length > 0 && isLikelyCartItem(obj[0])) {
      return obj;
    }

    // Object — search known property names
    if (typeof obj === 'object' && !Array.isArray(obj)) {
      const cartKeys = ['cartItems', 'cart_items', 'carts', 'info', 'list', 'items', 'cartList', 'goods', 'goodsList'];
      for (const key of cartKeys) {
        if (obj[key]) {
          const result = findCartItemsInObject(obj[key], depth + 1);
          if (result.length > 0) return result;
        }
      }
      // Fallback: search all keys
      for (const key of Object.keys(obj)) {
        if (typeof obj[key] === 'object' && obj[key] !== null) {
          const result = findCartItemsInObject(obj[key], depth + 1);
          if (result.length > 0) return result;
        }
      }
    }

    return [];
  }

  /**
   * Heuristic: does this object look like a cart item?
   */
  function isLikelyCartItem(item) {
    if (!item || typeof item !== 'object') return false;
    const keys = Object.keys(item).map(k => k.toLowerCase());
    const indicators = ['sku', 'goods_id', 'product_name', 'goods_sn', 'price', 'quantity', 'qty', 'product_img', 'goods_img'];
    return indicators.filter(i => keys.some(k => k.includes(i))).length >= 2;
  }

  /**
   * Normalize a raw Shein cart item object into our schema
   */
  function normalizeSheinItem(raw) {
    const keys = Object.keys(raw);
    const find = (patterns) => {
      for (const p of patterns) {
        for (const k of keys) {
          if (k.toLowerCase().includes(p.toLowerCase())) return raw[k];
        }
      }
      return null;
    };

    return {
      product_name: find(['goods_name', 'product_name', 'productName', 'name']) || 'Unknown',
      sku: String(find(['sku_code', 'sku_id', 'skuCode', 'sku', 'goods_sn', 'goodsSn', 'goods_id', 'goodsId', 'product_code']) || ''),
      price: parseFloat(find(['unitPrice', 'unit_price', 'retailPrice', 'retail_price', 'sale_price', 'price']) || 0),
      image_url: find(['product_img', 'goods_img', 'goodsImg', 'product_image', 'image', 'img']) || '',
      size: find(['attr_value_name_en', 'size', 'sizeAttr', 'selected_size']) || '',
      color: find(['color', 'colour', 'colorName', 'color_name', 'main_color']) || '',
      quantity: parseInt(find(['quantity', 'qty', 'num']) || 1),
    };
  }

  /**
   * Strategy 2: Direct DOM traversal on the Shein cart page
   * Uses multiple selector strategies since Shein changes class names frequently
   */
  function extractSheinFromDOM() {
    const items = [];

    // Shein cart item selectors (multiple generations of their UI)
    const containerSelectors = [
      '.cart-item-v2',
      '.cart-item',
      '[class*="cart"][class*="item"]',
      '[class*="CartItem"]',
      '.j-cart-item',
      '[data-goods-id]',
      '.shopping-cart__item',
      'li[class*="cart"]',
    ];

    let containers = [];
    for (const sel of containerSelectors) {
      containers = document.querySelectorAll(sel);
      if (containers.length > 0) break;
    }

    // Fallback: find any element with cart-like structure
    if (containers.length === 0) {
      containers = findCartContainersByHeuristic();
    }

    for (const container of containers) {
      try {
        const item = extractItemFromElement(container);
        if (item.product_name && item.product_name !== 'Unknown') {
          items.push(item);
        }
      } catch { /* skip malformed items */ }
    }

    return items;
  }

  /**
   * Heuristic container finder: look for repeated siblings with images and prices
   */
  function findCartContainersByHeuristic() {
    const candidates = document.querySelectorAll('[class*="goods"], [class*="product"], [class*="item"]');
    const groups = new Map();

    for (const el of candidates) {
      const className = el.className;
      if (!groups.has(className)) groups.set(className, []);
      groups.get(className).push(el);
    }

    // The cart item class will have multiple instances (one per item)
    for (const [, elements] of groups) {
      if (elements.length >= 1 && elements.length <= 100) {
        // Check if these contain images and text (likely product cards)
        const hasImages = elements[0].querySelector('img') !== null;
        const hasText = elements[0].textContent.trim().length > 10;
        if (hasImages && hasText) return elements;
      }
    }

    return [];
  }

  /**
   * Extract a single cart item from a DOM element
   */
  function extractItemFromElement(el) {
    return {
      product_name: extractProductName(el),
      sku: extractSku(el),
      price: extractPrice(el),
      image_url: extractImageUrl(el),
      size: extractAttribute(el, 'size'),
      color: extractAttribute(el, 'color'),
      quantity: extractQuantity(el),
    };
  }

  function extractProductName(el) {
    const selectors = [
      '[class*="name"] a', '[class*="Name"] a',
      '[class*="title"] a', '[class*="Title"] a',
      'a[class*="goods"]', 'a[class*="product"]',
      '.product-name', '.goods-name', '.cart-item__name',
      'a[href*="product"]', 'a[href*="goods"]',
    ];
    for (const sel of selectors) {
      const node = el.querySelector(sel);
      if (node?.textContent?.trim()) return node.textContent.trim();
    }
    // Fallback: first link with substantial text
    const links = el.querySelectorAll('a');
    for (const a of links) {
      const text = a.textContent?.trim();
      if (text && text.length > 5 && text.length < 200) return text;
    }
    return 'Unknown';
  }

  function extractSku(el) {
    // 1. data attributes
    const dataAttrs = ['data-sku', 'data-sku-id', 'data-goods-id', 'data-id', 'data-goods-sn', 'data-product-id'];
    for (const attr of dataAttrs) {
      const val = el.getAttribute(attr) || el.querySelector(`[${attr}]`)?.getAttribute(attr);
      if (val) return val;
    }

    // 2. Hidden inputs
    const inputs = el.querySelectorAll('input[type="hidden"]');
    for (const inp of inputs) {
      const name = (inp.name || inp.id || '').toLowerCase();
      if (name.includes('sku') || name.includes('goods_id') || name.includes('product_id')) {
        return inp.value;
      }
    }

    // 3. Text content matching SKU patterns (sw, sz, or numeric Shein IDs)
    const allText = el.textContent || '';
    const skuPatterns = [
      /\b(s[wz]\d{10,20})\b/i,           // sw2212345678901 or sz format
      /\bSKU[:\s]*([A-Z0-9-]+)\b/i,      // SKU: ABC123
      /\b(sk\d{6,15})\b/i,               // sk format  
      /\bGoods\s*ID[:\s]*(\d+)/i,         // Goods ID: 12345
      /\b(\d{8,15})\b/,                   // Pure numeric (8-15 digits, likely Shein goods_id)
    ];
    for (const pattern of skuPatterns) {
      const match = allText.match(pattern);
      if (match) return match[1];
    }

    // 4. From product URL in any link
    const link = el.querySelector('a[href*="product"], a[href*="goods"]');
    if (link) {
      const href = link.getAttribute('href') || '';
      const urlMatch = href.match(/[/-]p-(\d+)/i) || href.match(/goods[/-](\d+)/i) || href.match(/-cat-(\d+)/i);
      if (urlMatch) return urlMatch[1];
    }

    return '';
  }

  function extractPrice(el) {
    const selectors = [
      '[class*="price"]', '[class*="Price"]',
      '.sale-price', '.retail-price',
      '[class*="amount"]', '[class*="cost"]',
    ];
    for (const sel of selectors) {
      const nodes = el.querySelectorAll(sel);
      for (const node of nodes) {
        const text = node.textContent?.trim() || '';
        const match = text.match(/[\d]+[.,]?\d*/);
        if (match) return parseFloat(match[0].replace(',', '.'));
      }
    }
    return 0;
  }

  function extractImageUrl(el) {
    const img = el.querySelector('img[src*="img.shein"], img[src*="img.ltwebstatic"], img[class*="goods"], img[class*="product"], img');
    if (img) {
      return img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
    }
    // Check for background images
    const bgEl = el.querySelector('[style*="background-image"]');
    if (bgEl) {
      const match = bgEl.style.backgroundImage.match(/url\(["']?(.+?)["']?\)/);
      if (match) return match[1];
    }
    return '';
  }

  function extractAttribute(el, attrType) {
    // Look for labeled attributes: "Size: M" or "Color: Black"
    const attrSelectors = [
      `[class*="${attrType}"]`, `[class*="${attrType.charAt(0).toUpperCase() + attrType.slice(1)}"]`,
      `[class*="attr"]`, `[class*="variant"]`, `[class*="spec"]`,
    ];
    for (const sel of attrSelectors) {
      const nodes = el.querySelectorAll(sel);
      for (const node of nodes) {
        const text = node.textContent?.trim() || '';
        if (text.length > 0 && text.length < 50) {
          // Check if this specifically mentions the attribute type
          const regex = new RegExp(`${attrType}[:\\s]+(.+)`, 'i');
          const match = text.match(regex);
          if (match) return match[1].trim();
          // If the element class specifically contains the attr type, use full text
          if ((node.className || '').toLowerCase().includes(attrType)) return text;
        }
      }
    }

    // Fallback: search through text nodes
    const allText = el.textContent || '';
    const regex = new RegExp(`${attrType}[:\\s]+([A-Za-z0-9\\s/]+)`, 'i');
    const match = allText.match(regex);
    if (match) return match[1].trim().substring(0, 30);

    return '';
  }

  function extractQuantity(el) {
    // Quantity inputs
    const qtyInput = el.querySelector('input[type="number"], input[class*="qty"], input[class*="quantity"], input[class*="num"]');
    if (qtyInput) return parseInt(qtyInput.value) || 1;

    // Quantity text
    const qtySelectors = ['[class*="qty"]', '[class*="quantity"]', '[class*="num"]', '[class*="count"]'];
    for (const sel of qtySelectors) {
      const node = el.querySelector(sel);
      if (node) {
        const num = parseInt(node.textContent?.trim());
        if (!isNaN(num) && num > 0 && num < 1000) return num;
      }
    }

    return 1;
  }

  // ─── TRENDYOL EXTRACTION ───────────────────────────────────

  function extractTrendyolCart() {
    let items = [];

    // Strategy 1: Trendyol embeds cart in __NEXT_DATA__ or window.__TRENDYOL__
    const nextData = window.__NEXT_DATA__;
    if (nextData) {
      try {
        const cartItems = findCartItemsInObject(nextData);
        if (cartItems.length > 0) {
          items = cartItems.map(ci => ({
            product_name: ci.name || ci.productName || ci.title || 'Unknown',
            sku: String(ci.barcode || ci.sku || ci.merchantSku || ci.contentId || ''),
            price: parseFloat(ci.price || ci.unitPrice || 0),
            image_url: ci.imageUrl || ci.images?.[0] || '',
            size: ci.size || ci.selectedSize || '',
            color: ci.color || ci.selectedColor || '',
            quantity: parseInt(ci.quantity || 1),
          }));
          return { success: true, platform: 'trendyol', strategy: 'next_data', items };
        }
      } catch { /* fall through */ }
    }

    // Strategy 2: DOM traversal
    const containers = document.querySelectorAll('.pb-basket-item, [class*="basket-item"], [class*="cart-item"]');
    for (const container of containers) {
      try {
        items.push(extractItemFromElement(container));
      } catch { /* skip */ }
    }

    if (items.length > 0) {
      return { success: true, platform: 'trendyol', strategy: 'dom_traversal', items };
    }

    return { success: false, error: 'Could not extract items from Trendyol cart.', items: [] };
  }

  // ─── Message Listener (for popup.js communication) ─────────

  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'extractCart') {
      const result = extractCartItems();
      sendResponse(result);
    }
    return true; // Keep the message channel open for async
  });

  // Also expose globally for debugging in DevTools
  window.__estore_extract = extractCartItems;

  console.log('[eStore] Cart Extractor loaded. Platform:', isShein ? 'Shein' : isTrendyol ? 'Trendyol' : 'Unknown');
})();
