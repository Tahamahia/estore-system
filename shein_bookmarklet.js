/**
 * Shein Cart Bookmarklet — eStore Management System
 * ===================================================
 * Saves as a Chrome/Firefox bookmark with URL = javascript:<minified code>
 *
 * USAGE:
 *   1. Open Chrome → Bookmarks Bar → Right-click → Add page
 *   2. Set Name: "📦 نسخ سلة شي إن"
 *   3. Set URL: copy the entire one-liner below (starting with javascript:)
 *   4. On any Shein cart or shared-cart page, click the bookmark
 *   5. An alert confirms success — then go to the app and click "لصق بيانات السلة"
 *
 * ONE-LINER (paste this as the bookmark URL):
 * -------------------------------------------
 * javascript:(function(){'use strict';var items=[];function toPrice(v){if(!v)return 0;if(typeof v==='number')return v;if(typeof v==='string')return parseFloat(v)||0;if(v.amount)return parseFloat(v.amount)||0;if(v.usdAmount)return parseFloat(v.usdAmount)||0;return 0;}function getAttrs(list){var size='',color='';if(!Array.isArray(list))return{size:size,color:color};list.forEach(function(a){var n=String(a.attr_name||a.name||'').toLowerCase();var v=String(a.attr_value_name||a.attr_value||a.value||'');if(n.indexOf('size')!==-1)size=v;if(n.indexOf('color')!==-1||n.indexOf('colour')!==-1)color=v;});return{size:size,color:color};}function buildUrl(g){var slug=g.goods_url_name||g.goodsUrlName||'';var id=g.goods_id||'';if(slug&&id)return'https://www.shein.com/p-'+slug+'-p-'+id+'.html';var sn=g.goods_sn||g.goodsSn||'';if(sn)return'https://www.shein.com/brand-p-'+sn+'.html';return window.location.href;}function goodsToItem(g){var name=g.goods_name||g.product_name||g.name||'';if(!name)return null;var attrs=getAttrs(g.attr_value_list||g.attrValueList||g.skc_sale_attr||[]);return{name:name,url:buildUrl(g),sku:String(g.goods_sn||g.goodsSn||g.sku||''),price:toPrice(g.salePrice||g.sale_price||g.unitPrice||g.price),qty:Math.max(1,parseInt(g.quantity||g.buy_num||1,10)||1),size:attrs.size,color:attrs.color};}function hunt(obj,depth){if(!depth)depth=0;if(depth>8||!obj||typeof obj!=='object')return[];if(Array.isArray(obj)){if(obj.length>0&&obj[0]&&obj[0].goods_name){var out=[];obj.forEach(function(g){var i=goodsToItem(g);if(i)out.push(i);});if(out.length)return out;}for(var i=0;i<Math.min(obj.length,30);i++){var f=hunt(obj[i],depth+1);if(f.length)return f;}return[];}var priority=['carts','cartList','cart_list','goods_list','goodsList','products','items','result'];for(var j=0;j<priority.length;j++){if(obj[priority[j]]){var r=hunt(obj[priority[j]],depth+1);if(r.length)return r;}}var keys=Object.keys(obj).slice(0,50);for(var k=0;k<keys.length;k++){var q=hunt(obj[keys[k]],depth+1);if(q.length)return q;}return[];}if(window.__PRELOADED_STATE__)items=hunt(window.__PRELOADED_STATE__);if(!items.length&&window.gbCartData)items=hunt(window.gbCartData);if(!items.length){var scripts=document.querySelectorAll('script:not([src])');for(var s=0;s<scripts.length&&!items.length;s++){var text=scripts[s].textContent||'';['__PRELOADED_STATE__','gbCartData','cartInfo'].forEach(function(p){if(items.length)return;var idx=text.indexOf(p);if(idx===-1)return;var start=idx+p.length;while(start<text.length&&' \t\n=;'.indexOf(text[start])!==-1)start++;if(text[start]!=='{'&&text[start]!=='[')return;try{var depth=0,inStr=false,esc=false;for(var i=start;i<Math.min(start+600000,text.length);i++){var c=text[i];if(esc){esc=false;continue;}if(c==='\\'&&inStr){esc=true;continue;}if(c==='"'){inStr=!inStr;continue;}if(inStr)continue;if(c==='{'||c==='[')depth++;else if(c==='}'||c===']'){if(--depth===0){var parsed=JSON.parse(text.slice(start,i+1));var found=hunt(parsed);if(found.length)items=found;break;}}}}catch(e){}});}}if(!items.length){alert('❌ لم يتم العثور على بيانات السلة.\n\nتأكد أنك على صفحة سلة شي إن أو صفحة منتج مشارك.');return;}var json=JSON.stringify(items);function doCopy(t){if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(function(){alert('✅ تم نسخ بيانات السلة!\nعدد المنتجات: '+items.length+'\nاذهبي للمنظومة واضغطي لصق.');}).catch(function(){fallback(t);});}else{fallback(t);}}function fallback(t){var ta=document.createElement('textarea');ta.value=t;ta.style.cssText='position:fixed;top:-9999px;left:-9999px;opacity:0';document.body.appendChild(ta);ta.select();ta.setSelectionRange(0,t.length);try{var ok=document.execCommand('copy');alert(ok?'✅ تم نسخ بيانات السلة!\nعدد المنتجات: '+items.length+'\nاذهبي للمنظومة واضغطي لصق.':'❌ فشل النسخ — انسخ النص يدوياً.');}catch(e){alert('❌ فشل النسخ: '+e.message);}finally{document.body.removeChild(ta);}}doCopy(json);})();
 *
 * ─────────────────────────────────────────────────────────────
 * READABLE SOURCE (same logic, expanded for maintainability):
 * ─────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  /** ── Helpers ──────────────────────────────────────────── */

  function toPrice(v) {
    if (!v) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') return parseFloat(v) || 0;
    if (v.amount)    return parseFloat(v.amount)    || 0;
    if (v.usdAmount) return parseFloat(v.usdAmount) || 0;
    return 0;
  }

  function getAttrs(list) {
    var size = '', color = '';
    if (!Array.isArray(list)) return { size: size, color: color };
    list.forEach(function (a) {
      var n = String(a.attr_name || a.name || '').toLowerCase();
      var v = String(a.attr_value_name || a.attr_value || a.value || '');
      if (n.indexOf('size')   !== -1) size  = v;
      if (n.indexOf('color')  !== -1 || n.indexOf('colour') !== -1) color = v;
    });
    return { size: size, color: color };
  }

  function buildUrl(g) {
    var slug = g.goods_url_name || g.goodsUrlName || '';
    var id   = g.goods_id || '';
    if (slug && id) return 'https://www.shein.com/p-' + slug + '-p-' + id + '.html';
    var sn = g.goods_sn || g.goodsSn || '';
    if (sn) return 'https://www.shein.com/brand-p-' + sn + '.html';
    return window.location.href;
  }

  function goodsToItem(g) {
    var name = g.goods_name || g.product_name || g.name || '';
    if (!name) return null;
    var attrs = getAttrs(g.attr_value_list || g.attrValueList || g.skc_sale_attr || []);
    return {
      name:  name,
      url:   buildUrl(g),
      sku:   String(g.goods_sn || g.goodsSn || g.sku || ''),
      price: toPrice(g.salePrice || g.sale_price || g.unitPrice || g.price),
      qty:   Math.max(1, parseInt(g.quantity || g.buy_num || 1, 10) || 1),
      size:  attrs.size,
      color: attrs.color,
    };
  }

  /** Recursively hunts for arrays whose first element has `goods_name`. */
  function hunt(obj, depth) {
    if (!depth) depth = 0;
    if (depth > 8 || !obj || typeof obj !== 'object') return [];

    if (Array.isArray(obj)) {
      if (obj.length > 0 && obj[0] && obj[0].goods_name) {
        var out = [];
        obj.forEach(function (g) { var i = goodsToItem(g); if (i) out.push(i); });
        if (out.length) return out;
      }
      for (var i = 0; i < Math.min(obj.length, 30); i++) {
        var found = hunt(obj[i], depth + 1);
        if (found.length) return found;
      }
      return [];
    }

    var priority = ['carts', 'cartList', 'cart_list', 'goods_list', 'goodsList', 'products', 'items', 'result'];
    for (var j = 0; j < priority.length; j++) {
      if (obj[priority[j]]) {
        var r = hunt(obj[priority[j]], depth + 1);
        if (r.length) return r;
      }
    }
    var keys = Object.keys(obj).slice(0, 50);
    for (var k = 0; k < keys.length; k++) {
      var q = hunt(obj[keys[k]], depth + 1);
      if (q.length) return q;
    }
    return [];
  }

  /** ── Strategy 1: window.__PRELOADED_STATE__ ───────────── */
  var items = [];
  if (window.__PRELOADED_STATE__) {
    items = hunt(window.__PRELOADED_STATE__);
  }

  /** ── Strategy 2: window.gbCartData ────────────────────── */
  if (!items.length && window.gbCartData) {
    items = hunt(window.gbCartData);
  }

  /** ── Strategy 3: scan inline <script> tags ────────────── */
  if (!items.length) {
    var scripts = document.querySelectorAll('script:not([src])');
    for (var s = 0; s < scripts.length && !items.length; s++) {
      var text = scripts[s].textContent || '';
      ['__PRELOADED_STATE__', 'gbCartData', 'cartInfo'].forEach(function (marker) {
        if (items.length) return;
        var idx = text.indexOf(marker);
        if (idx === -1) return;
        var start = idx + marker.length;
        while (start < text.length && ' \t\n=;'.indexOf(text[start]) !== -1) start++;
        if (text[start] !== '{' && text[start] !== '[') return;
        try {
          var depth = 0, inStr = false, esc = false;
          for (var i = start; i < Math.min(start + 600000, text.length); i++) {
            var c = text[i];
            if (esc)                    { esc = false; continue; }
            if (c === '\\' && inStr)    { esc = true;  continue; }
            if (c === '"')              { inStr = !inStr; continue; }
            if (inStr)                  continue;
            if (c === '{' || c === '[') { depth++; continue; }
            if (c === '}' || c === ']') {
              if (--depth === 0) {
                var parsed = JSON.parse(text.slice(start, i + 1));
                var found  = hunt(parsed);
                if (found.length) items = found;
                break;
              }
            }
          }
        } catch (e) { /* keep trying */ }
      });
    }
  }

  /** ── No data found ─────────────────────────────────────── */
  if (!items.length) {
    alert(
      '❌ لم يتم العثور على بيانات السلة.\n\n' +
      'تأكد أنك على صفحة سلة شي إن أو صفحة منتج مشارك.\n' +
      'إذا كان الموقع يعرض نافذة تسجيل دخول، سجلي أولاً ثم حاولي مجدداً.'
    );
    return;
  }

  var json = JSON.stringify(items);

  /** ── Copy to clipboard ─────────────────────────────────── */
  function showSuccess() {
    alert(
      '✅ تم نسخ بيانات السلة بنجاح!\n' +
      'عدد المنتجات: ' + items.length + '\n\n' +
      'اذهبي للمنظومة واضغطي "لصق بيانات السلة".'
    );
  }

  function fallbackCopy(t) {
    var ta = document.createElement('textarea');
    ta.value = t;
    ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0;';
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, t.length);
    try {
      var ok = document.execCommand('copy');
      if (ok) { showSuccess(); }
      else    { alert('❌ فشل النسخ التلقائي — انسخ يدوياً من وحدة التحكم.'); }
    } catch (e) {
      alert('❌ فشل النسخ: ' + e.message);
    } finally {
      document.body.removeChild(ta);
    }
  }

  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(json)
      .then(showSuccess)
      .catch(function () { fallbackCopy(json); });
  } else {
    fallbackCopy(json);
  }
})();
