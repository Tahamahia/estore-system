import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt, buildRecomputeExternalShipmentStmt } from '../lib/orderStatus';

export const warehouseRoutes = new Hono<AppEnv>();

warehouseRoutes.post('/scan', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const { barcode } = await c.req.json<{ barcode: string }>();
  if (!barcode) return c.json({ error: 'barcode required' }, 400);

  // Lookup chain: item_uid → sku → tracking_number → primary key (ambiguity confirmation)
  let items = await c.env.DB.prepare(
    `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
     JOIN orders o ON oi.order_id = o.id LEFT JOIN customers c ON o.customer_id = c.id
     WHERE oi.item_uid = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
  ).bind(barcode, tenantId).all();

  // Fallback 2: Search by SKU (Shein/Trendyol physical barcode)
  if (!items.results?.length) {
    items = await c.env.DB.prepare(
      `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
       JOIN orders o ON oi.order_id = o.id LEFT JOIN customers c ON o.customer_id = c.id
       WHERE oi.sku = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(barcode, tenantId).all();
  }

  // Fallback 3: Search by external shipment tracking number
  if (!items.results?.length) {
    items = await c.env.DB.prepare(
      `SELECT oi.*, o.customer_id, c.full_name as customer_name
       FROM order_items oi
       JOIN orders o ON oi.order_id = o.id
       LEFT JOIN customers c ON o.customer_id = c.id
       JOIN external_shipments es ON oi.external_shipment_id = es.id
       WHERE es.tracking_number = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(barcode, tenantId).all();
  }

  // Fallback 4: Direct primary key lookup — used when the ambiguity dialog confirms
  // a specific item by passing its UUID back through the scanner input.
  if (!items.results?.length) {
    items = await c.env.DB.prepare(
      `SELECT oi.*, o.customer_id, c.full_name as customer_name FROM order_items oi
       JOIN orders o ON oi.order_id = o.id LEFT JOIN customers c ON o.customer_id = c.id
       WHERE oi.id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0`
    ).bind(barcode, tenantId).all();
  }

  if (!items.results?.length) return c.json({ found: false, barcode });

  if (items.results.length > 1) {
    return c.json({ found: true, ambiguous: true, candidates: items.results.map((i: any) => ({
      id: i.id, product_name: i.product_name, customer_name: i.customer_name, status: i.status,
    }))});
  }

  const item = items.results[0] as any;

  // Always advance to sorted regardless of prior status — warehouse workers
  // must never be blocked by a purchasing-side sync mistake.
  // When the item has an external shipment, recompute that shipment's derived
  // status in the same batch — sorting an item may complete the shipment.
  const shipmentId = item.external_shipment_id as string | null;
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE order_items SET status = 'sorted', sorted_at = datetime('now'),
       updated_at = datetime('now'), version = version + 1
       WHERE id = ? AND tenant_id = ? AND is_deleted = 0`
    ).bind(item.id, tenantId),
    buildRecomputeOrderStatusStmt(c.env.DB, item.order_id as string, tenantId),
    ...(shipmentId ? [buildRecomputeExternalShipmentStmt(c.env.DB, shipmentId, tenantId)] : []),
  ]);

  // Return bag-completion info so the UI can flash the right colour
  const progress = await c.env.DB.prepare(`
    SELECT
      COUNT(*) AS total_items,
      SUM(CASE WHEN status = 'sorted' THEN 1 ELSE 0 END) AS sorted_items
    FROM order_items
    WHERE order_id = ? AND tenant_id = ? AND is_deleted = 0
      AND status NOT IN ('cancelled','refunded','transferred_to_inventory','in_stock')
  `).bind(item.order_id as string, tenantId).first();

  const sorted = Number((progress as any)?.sorted_items ?? 0);
  const total  = Number((progress as any)?.total_items  ?? 0);

  // If the scanned item was on an external shipment, tell the UI how the
  // parcel is reconciling: how many of the shipment's live items have
  // physically arrived so far. Cheap — one small query per scan.
  let shipmentProgress: { arrived: number; expected: number } | undefined;
  if (shipmentId) {
    const row = await c.env.DB.prepare(`
      SELECT
        COALESCE(SUM(CASE
          WHEN status IN ('arrived_warehouse','sorted','ready_dispatch','dispatched','delivered')
          THEN 1 ELSE 0 END), 0) AS arrived,
        COALESCE(SUM(CASE
          WHEN status NOT IN ('cancelled','refunded','in_stock','transferred_to_inventory')
          THEN 1 ELSE 0 END), 0) AS expected
      FROM order_items
      WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(shipmentId, tenantId).first();
    shipmentProgress = {
      arrived: Number((row as any)?.arrived ?? 0),
      expected: Number((row as any)?.expected ?? 0),
    };
  }

  return c.json({
    found: true,
    ambiguous: false,
    item: { id: item.id, product_name: item.product_name, customer_name: item.customer_name, status: 'sorted' },
    order_progress: { sorted, total, complete: total > 0 && sorted === total },
    ...(shipmentProgress ? { shipment_progress: shipmentProgress } : {}),
  });
});

warehouseRoutes.post('/orphan', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const userId = c.get('user_id') as string;
  const { id, barcode, description, photo_url } = await c.req.json();
  if (!id) return c.json({ error: 'id required' }, 400);

  await c.env.DB.prepare(
    `INSERT INTO unassigned_items (id, tenant_id, barcode, description, photo_url, status, logged_by, created_at, updated_at, version)
     VALUES (?, ?, ?, ?, ?, 'pending', ?, datetime('now'), datetime('now'), 1)`
  ).bind(id, tenantId, barcode || null, description || null, photo_url || null, userId).run();

  return c.json({ message: 'Orphaned package logged', id }, 201);
});

warehouseRoutes.get('/scan-history', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(`
    SELECT oi.id, oi.product_name, oi.sku, oi.sorted_at,
           c.full_name AS customer_name
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    LEFT JOIN customers c ON o.customer_id = c.id
    WHERE oi.tenant_id = ? AND oi.status = 'sorted'
      AND DATE(oi.sorted_at) = DATE('now')
      AND oi.is_deleted = 0
    ORDER BY oi.sorted_at DESC
    LIMIT 100
  `).bind(tenantId).all();

  return c.json({ data: results.results });
});

warehouseRoutes.get('/orphans', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const results = await c.env.DB.prepare(
    `SELECT id, barcode, description, photo_url, status, logged_by, created_at
     FROM unassigned_items WHERE tenant_id = ? AND status = 'pending' ORDER BY created_at DESC`
  ).bind(tenantId).all();
  return c.json({ data: results.results });
});

warehouseRoutes.patch('/orphans/:id/resolve', requireRole('super_admin', 'store_manager', 'sorter'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const { resolution } = await c.req.json<{ resolution: 'matched' | 'discarded' }>();
  const result = await c.env.DB.prepare(
    `UPDATE unassigned_items SET status = ?, updated_at = datetime('now'), version = version + 1
     WHERE id = ? AND tenant_id = ?`
  ).bind(resolution, id, tenantId).run();
  if (result.meta.changes === 0) return c.json({ error: 'Not Found' }, 404);
  return c.json({ message: 'تم التحديث', id });
});
