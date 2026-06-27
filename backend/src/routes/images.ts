import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';

export const imageRoutes = new Hono<AppEnv>();

/**
 * POST /images/upload — Fetch external image URL → store in R2
 * 
 * Cloudflare Workers cannot use `sharp` (native Node module).
 * Strategy: Fetch image as ArrayBuffer, store directly in R2,
 * rely on Cloudflare Image Resizing (URL transformations) for thumbnails.
 */
imageRoutes.post('/upload', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    image_url: string;
    item_id: string;
  }>();

  if (!body.image_url || !body.item_id) {
    return c.json({ error: 'Bad Request', message: 'image_url and item_id are required' }, 400);
  }

  try {
    // Fetch the external image
    const response = await fetch(body.image_url, {
      headers: { 'User-Agent': 'eStore-ImageFetcher/1.0' },
    });

    if (!response.ok) {
      return c.json({ error: 'Bad Request', message: `Failed to fetch image: HTTP ${response.status}` }, 400);
    }

    const contentType = response.headers.get('content-type') || 'image/jpeg';
    const imageBuffer = await response.arrayBuffer();

    // Size guard: reject images > 10MB
    if (imageBuffer.byteLength > 10 * 1024 * 1024) {
      return c.json({ error: 'Bad Request', message: 'Image exceeds 10MB limit' }, 400);
    }

    // Determine file extension from content type
    const extMap: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
    };
    const ext = extMap[contentType] || 'jpg';
    const timestamp = Date.now();
    const r2Key = `${tenantId}/products/${body.item_id}_${timestamp}.${ext}`;

    // Upload to R2
    await c.env.MEDIA.put(r2Key, imageBuffer, {
      httpMetadata: { contentType },
      customMetadata: {
        tenant_id: tenantId,
        item_id: body.item_id,
        original_url: body.image_url,
      },
    });

    // Build the public R2 URL
    // In production, configure a custom domain for R2 public access
    const fullUrl = `/media/${r2Key}`;

    // Thumbnail via Cloudflare Image Resizing (URL transform)
    // Format: /cdn-cgi/image/width=150,quality=75/${fullUrl}
    const thumbUrl = `/cdn-cgi/image/width=150,quality=75,format=webp${fullUrl}`;

    // Update the order_item with the R2 URLs
    await c.env.DB.prepare(
      `UPDATE order_items 
       SET product_image_url = ?, product_thumb_url = ?, updated_at = datetime('now')
       WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(fullUrl, thumbUrl, body.item_id, tenantId).run();

    return c.json({
      message: 'Image uploaded to R2',
      full_url: fullUrl,
      thumb_url: thumbUrl,
      size_bytes: imageBuffer.byteLength,
    });
  } catch (err: any) {
    console.error('[IMAGE] Upload failed:', err);
    return c.json({ error: 'Internal Error', message: `Image processing failed: ${err.message}` }, 500);
  }
});

/**
 * POST /images/batch — Batch upload multiple images for order items
 */
imageRoutes.post('/batch', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id');
  const body = await c.req.json<{
    items: Array<{ item_id: string; image_url: string }>;
  }>();

  if (!body.items?.length) {
    return c.json({ error: 'Bad Request', message: 'items array is required' }, 400);
  }

  const results: Array<{ item_id: string; status: string; url?: string; error?: string }> = [];

  for (const item of body.items) {
    try {
      const response = await fetch(item.image_url, {
        headers: { 'User-Agent': 'eStore-ImageFetcher/1.0' },
      });

      if (!response.ok) {
        results.push({ item_id: item.item_id, status: 'failed', error: `HTTP ${response.status}` });
        continue;
      }

      const contentType = response.headers.get('content-type') || 'image/jpeg';
      const imageBuffer = await response.arrayBuffer();

      if (imageBuffer.byteLength > 10 * 1024 * 1024) {
        results.push({ item_id: item.item_id, status: 'failed', error: 'Exceeds 10MB' });
        continue;
      }

      const ext = contentType.includes('png') ? 'png' : contentType.includes('webp') ? 'webp' : 'jpg';
      const r2Key = `${tenantId}/products/${item.item_id}_${Date.now()}.${ext}`;

      await c.env.MEDIA.put(r2Key, imageBuffer, {
        httpMetadata: { contentType },
      });

      const fullUrl = `/media/${r2Key}`;

      await c.env.DB.prepare(
        `UPDATE order_items SET product_image_url = ?, updated_at = datetime('now')
         WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
      ).bind(fullUrl, item.item_id, tenantId).run();

      results.push({ item_id: item.item_id, status: 'ok', url: fullUrl });
    } catch (err: any) {
      results.push({ item_id: item.item_id, status: 'failed', error: err.message });
    }
  }

  return c.json({
    total: body.items.length,
    success: results.filter(r => r.status === 'ok').length,
    failed: results.filter(r => r.status === 'failed').length,
    results,
  });
});
