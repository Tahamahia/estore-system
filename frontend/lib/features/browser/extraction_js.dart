/// Cart extraction JavaScript — injected into the WebView
///
/// This is the EXACT SAME extraction logic from the Chrome Extension
/// content.js, minified into a single evaluable string.
/// Returns JSON: { success: bool, platform: String, items: [...] }

const String cartExtractionJs = r'''
(function() {
  'use strict';

  var hostname = window.location.hostname;
  var isShein = hostname.indexOf('shein') !== -1;
  var isTrendyol = hostname.indexOf('trendyol') !== -1;

  function extractCartItems() {
    try {
      if (isShein) return extractSheinCart();
      if (isTrendyol) return extractTrendyolCart();
      return { success: false, error: 'Unsupported platform: ' + hostname, items: [] };
    } catch (err) {
      return { success: false, error: 'Extraction failed: ' + err.message, items: [] };
    }
  }

  /* ── SHEIN ─────────────────────────────────────── */

  function extractSheinCart() {
    var items = extractSheinFromEmbeddedData();
    if (items.length > 0) return { success: true, platform: 'shein', strategy: 'embedded_json', items: items };

    items = extractSheinFromDOM();
    if (items.length > 0) return { success: true, platform: 'shein', strategy: 'dom_traversal', items: items };

    return { success: false, error: 'Could not extract items. Ensure you are on the Shein cart page with items visible.', items: [] };
  }

  function extractSheinFromEmbeddedData() {
    var items = [];
    var stateKeys = ['__cart_data', 'gbCartSsrData', '__INITIAL_STATE__', 'gbCartInfo', '__NEXT_DATA__'];

    for (var i = 0; i < stateKeys.length; i++) {
      try {
        var raw = window[stateKeys[i]];
        if (!raw) continue;
        var data = (typeof raw === 'string') ? JSON.parse(raw) : raw;
        var cartItems = findCartItemsInObject(data, 0);
        if (cartItems.length > 0) {
          for (var j = 0; j < cartItems.length; j++) {
            items.push(normalizeSheinItem(cartItems[j]));
          }
          return items;
        }
      } catch(e) {}
    }

    var scripts = document.querySelectorAll('script[type="application/json"], script:not([src])');
    for (var s = 0; s < scripts.length; s++) {
      try {
        var text = (scripts[s].textContent || '').trim();
        if (!text || text.length < 50 || text.indexOf('cart') === -1) continue;
        var sdata = JSON.parse(text);
        var sitems = findCartItemsInObject(sdata, 0);
        if (sitems.length > 0) {
          for (var k = 0; k < sitems.length; k++) items.push(normalizeSheinItem(sitems[k]));
          return items;
        }
      } catch(e) {}
    }
    return items;
  }

  function findCartItemsInObject(obj, depth) {
    if (depth > 8 || !obj) return [];
    if (Array.isArray(obj) && obj.length > 0 && isLikelyCartItem(obj[0])) return obj;
    if (typeof obj === 'object' && !Array.isArray(obj)) {
      var cartKeys = ['cartItems','cart_items','carts','info','list','items','cartList','goods','goodsList'];
      for (var i = 0; i < cartKeys.length; i++) {
        if (obj[cartKeys[i]]) {
          var r = findCartItemsInObject(obj[cartKeys[i]], depth + 1);
          if (r.length > 0) return r;
        }
      }
      var keys = Object.keys(obj);
      for (var j = 0; j < keys.length; j++) {
        if (typeof obj[keys[j]] === 'object' && obj[keys[j]] !== null) {
          var r2 = findCartItemsInObject(obj[keys[j]], depth + 1);
          if (r2.length > 0) return r2;
        }
      }
    }
    return [];
  }

  function isLikelyCartItem(item) {
    if (!item || typeof item !== 'object') return false;
    var keys = Object.keys(item).map(function(k){return k.toLowerCase();});
    var indicators = ['sku','goods_id','product_name','goods_sn','price','quantity','qty','product_img','goods_img'];
    var count = 0;
    for (var i = 0; i < indicators.length; i++) {
      for (var j = 0; j < keys.length; j++) {
        if (keys[j].indexOf(indicators[i]) !== -1) { count++; break; }
      }
    }
    return count >= 2;
  }

  function normalizeSheinItem(raw) {
    var keys = Object.keys(raw);
    function find(patterns) {
      for (var i = 0; i < patterns.length; i++) {
        for (var j = 0; j < keys.length; j++) {
          if (keys[j].toLowerCase().indexOf(patterns[i].toLowerCase()) !== -1) return raw[keys[j]];
        }
      }
      return null;
    }
    return {
      product_name: find(['goods_name','product_name','productName','name']) || 'Unknown',
      sku: String(find(['sku_code','sku_id','skuCode','sku','goods_sn','goodsSn','goods_id','goodsId','product_code']) || ''),
      price: parseFloat(find(['unitPrice','unit_price','retailPrice','retail_price','sale_price','price']) || 0),
      image_url: find(['product_img','goods_img','goodsImg','product_image','image','img']) || '',
      size: find(['attr_value_name_en','size','sizeAttr','selected_size']) || '',
      color: find(['color','colour','colorName','color_name','main_color']) || '',
      quantity: parseInt(find(['quantity','qty','num']) || 1)
    };
  }

  /* ── SHEIN DOM FALLBACK ─────────────────────────── */

  function extractSheinFromDOM() {
    var items = [];
    var selectors = ['.cart-item-v2','.cart-item','[class*="cart"][class*="item"]','[class*="CartItem"]','.j-cart-item','[data-goods-id]','.shopping-cart__item','li[class*="cart"]'];
    var containers = [];
    for (var i = 0; i < selectors.length; i++) {
      containers = document.querySelectorAll(selectors[i]);
      if (containers.length > 0) break;
    }
    if (containers.length === 0) containers = findCartContainersByHeuristic();
    for (var j = 0; j < containers.length; j++) {
      try {
        var item = extractItemFromElement(containers[j]);
        if (item.product_name && item.product_name !== 'Unknown') items.push(item);
      } catch(e) {}
    }
    return items;
  }

  function findCartContainersByHeuristic() {
    var candidates = document.querySelectorAll('[class*="goods"],[class*="product"],[class*="item"]');
    var groups = {};
    for (var i = 0; i < candidates.length; i++) {
      var cn = candidates[i].className;
      if (!groups[cn]) groups[cn] = [];
      groups[cn].push(candidates[i]);
    }
    var keys = Object.keys(groups);
    for (var j = 0; j < keys.length; j++) {
      var els = groups[keys[j]];
      if (els.length >= 1 && els.length <= 100) {
        if (els[0].querySelector('img') && (els[0].textContent||'').trim().length > 10) return els;
      }
    }
    return [];
  }

  function extractItemFromElement(el) {
    return {
      product_name: extractProductName(el),
      sku: extractSku(el),
      price: extractPrice(el),
      image_url: extractImageUrl(el),
      size: extractAttribute(el, 'size'),
      color: extractAttribute(el, 'color'),
      quantity: extractQuantity(el)
    };
  }

  function extractProductName(el) {
    var sels = ['[class*="name"] a','[class*="Name"] a','[class*="title"] a','a[class*="goods"]','a[class*="product"]','.product-name','.goods-name','a[href*="product"]','a[href*="goods"]'];
    for (var i = 0; i < sels.length; i++) {
      var n = el.querySelector(sels[i]);
      if (n && (n.textContent||'').trim()) return n.textContent.trim();
    }
    var links = el.querySelectorAll('a');
    for (var j = 0; j < links.length; j++) {
      var t = (links[j].textContent||'').trim();
      if (t.length > 5 && t.length < 200) return t;
    }
    return 'Unknown';
  }

  function extractSku(el) {
    var attrs = ['data-sku','data-sku-id','data-goods-id','data-id','data-goods-sn','data-product-id'];
    for (var i = 0; i < attrs.length; i++) {
      var v = el.getAttribute(attrs[i]);
      if (!v) { var child = el.querySelector('['+attrs[i]+']'); if (child) v = child.getAttribute(attrs[i]); }
      if (v) return v;
    }
    var inputs = el.querySelectorAll('input[type="hidden"]');
    for (var j = 0; j < inputs.length; j++) {
      var nm = (inputs[j].name||inputs[j].id||'').toLowerCase();
      if (nm.indexOf('sku') !== -1 || nm.indexOf('goods_id') !== -1) return inputs[j].value;
    }
    var text = el.textContent || '';
    var patterns = [/\b(s[wz]\d{10,20})\b/i, /\bSKU[:\s]*([A-Z0-9-]+)\b/i, /\b(sk\d{6,15})\b/i, /\bGoods\s*ID[:\s]*(\d+)/i, /\b(\d{8,15})\b/];
    for (var k = 0; k < patterns.length; k++) {
      var m = text.match(patterns[k]);
      if (m) return m[1];
    }
    var link = el.querySelector('a[href*="product"],a[href*="goods"]');
    if (link) {
      var href = link.getAttribute('href') || '';
      var um = href.match(/[/-]p-(\d+)/i) || href.match(/goods[/-](\d+)/i);
      if (um) return um[1];
    }
    return '';
  }

  function extractPrice(el) {
    var sels = ['[class*="price"]','[class*="Price"]','.sale-price','[class*="amount"]'];
    for (var i = 0; i < sels.length; i++) {
      var nodes = el.querySelectorAll(sels[i]);
      for (var j = 0; j < nodes.length; j++) {
        var t = (nodes[j].textContent||'').trim();
        var m = t.match(/[\d]+[.,]?\d*/);
        if (m) return parseFloat(m[0].replace(',','.'));
      }
    }
    return 0;
  }

  function extractImageUrl(el) {
    var img = el.querySelector('img[src*="img.shein"],img[src*="img.ltwebstatic"],img[class*="goods"],img[class*="product"],img');
    if (img) return img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
    var bg = el.querySelector('[style*="background-image"]');
    if (bg) { var m = bg.style.backgroundImage.match(/url\(["']?(.+?)["']?\)/); if (m) return m[1]; }
    return '';
  }

  function extractAttribute(el, attrType) {
    var sels = ['[class*="'+attrType+'"]','[class*="attr"]','[class*="variant"]','[class*="spec"]'];
    for (var i = 0; i < sels.length; i++) {
      var nodes = el.querySelectorAll(sels[i]);
      for (var j = 0; j < nodes.length; j++) {
        var t = (nodes[j].textContent||'').trim();
        if (t.length > 0 && t.length < 50) {
          var rx = new RegExp(attrType+'[:\\\\s]+(.+)','i');
          var m = t.match(rx);
          if (m) return m[1].trim();
          if ((nodes[j].className||'').toLowerCase().indexOf(attrType) !== -1) return t;
        }
      }
    }
    var allText = el.textContent || '';
    var rx2 = new RegExp(attrType+'[:\\\\s]+([A-Za-z0-9\\\\s/]+)','i');
    var m2 = allText.match(rx2);
    if (m2) return m2[1].trim().substring(0,30);
    return '';
  }

  function extractQuantity(el) {
    var qi = el.querySelector('input[type="number"],input[class*="qty"],input[class*="quantity"]');
    if (qi) return parseInt(qi.value) || 1;
    var sels = ['[class*="qty"]','[class*="quantity"]','[class*="num"]','[class*="count"]'];
    for (var i = 0; i < sels.length; i++) {
      var n = el.querySelector(sels[i]);
      if (n) { var v = parseInt((n.textContent||'').trim()); if (!isNaN(v) && v > 0 && v < 1000) return v; }
    }
    return 1;
  }

  /* ── TRENDYOL ───────────────────────────────────── */

  function extractTrendyolCart() {
    var items = [];
    var nd = window.__NEXT_DATA__;
    if (nd) {
      try {
        var ci = findCartItemsInObject(nd, 0);
        if (ci.length > 0) {
          items = ci.map(function(c) {
            return {
              product_name: c.name||c.productName||c.title||'Unknown',
              sku: String(c.barcode||c.sku||c.merchantSku||c.contentId||''),
              price: parseFloat(c.price||c.unitPrice||0),
              image_url: c.imageUrl||(c.images?c.images[0]:'')||'',
              size: c.size||c.selectedSize||'',
              color: c.color||c.selectedColor||'',
              quantity: parseInt(c.quantity||1)
            };
          });
          return { success: true, platform: 'trendyol', strategy: 'next_data', items: items };
        }
      } catch(e) {}
    }
    var containers = document.querySelectorAll('.pb-basket-item,[class*="basket-item"],[class*="cart-item"]');
    for (var i = 0; i < containers.length; i++) {
      try { items.push(extractItemFromElement(containers[i])); } catch(e) {}
    }
    if (items.length > 0) return { success: true, platform: 'trendyol', strategy: 'dom_traversal', items: items };
    return { success: false, error: 'Could not extract from Trendyol cart.', items: [] };
  }

  return JSON.stringify(extractCartItems());
})()
''';
