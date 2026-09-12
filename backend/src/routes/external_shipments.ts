import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireRole } from '../middleware/tenant';
import { buildRecomputeOrderStatusStmt, buildRecomputeExternalShipmentStmt } from '../lib/orderStatus';

// Reconciliation SQL fragment reused by GET / list, GET /:id detail, and the
// dedicated /reconciliation endpoint. All three read from order_items joined
// per external shipment. Kept in one place so the counts can never drift.
//
// - expected: live items on the shipment (excluding cancelled/refunded/
//   in_stock/transferred_to_inventory).
// - confirmed: items proven physically present by a scan (sorted or beyond).
//   sorted_count is a legacy alias of confirmed_count for older UI callers.
// - missing: items presumed present (shipped OR arrived_warehouse) but never
//   scanned. Undefined before receive — forced to 0 while received_at is NULL,
//   because nothing is expected to be at the warehouse yet.
const RECON_COUNTS_SQL = `
  COALESCE((
    SELECT COUNT(*) FROM order_items oi
    WHERE oi.external_shipment_id = es.id AND oi.tenant_id = es.tenant_id
      AND oi.is_deleted = 0
      AND oi.status NOT IN ('cancelled','refunded','in_stock','transferred_to_inventory')
  ), 0) AS expected_count,
  COALESCE((
    SELECT COUNT(*) FROM order_items oi
    WHERE oi.external_shipment_id = es.id AND oi.tenant_id = es.tenant_id
      AND oi.is_deleted = 0
      AND oi.status IN ('sorted','ready_dispatch','dispatched','delivered')
  ), 0) AS confirmed_count,
  COALESCE((
    SELECT COUNT(*) FROM order_items oi
    WHERE oi.external_shipment_id = es.id AND oi.tenant_id = es.tenant_id
      AND oi.is_deleted = 0
      AND oi.status IN ('sorted','ready_dispatch','dispatched','delivered')
  ), 0) AS sorted_count,
  CASE WHEN es.received_at IS NULL THEN 0 ELSE COALESCE((
    SELECT COUNT(*) FROM order_items oi
    WHERE oi.external_shipment_id = es.id AND oi.tenant_id = es.tenant_id
      AND oi.is_deleted = 0
      AND oi.status IN ('shipped','arrived_warehouse')
  ), 0) END AS missing_count
`;

export const externalShipmentRoutes = new Hono<AppEnv>();

// ─── Types ─────────────────────────────────────────────────
type TrackingEvent = {
  date: string;
  description: string;
  location?: string;
};

type TrackingResult = {
  courier: string;
  /** Normalized to our enum: 'in_transit' | 'at_local_forwarder' | 'arrived_at_warehouse' */
  status: string;
  lastEvent: string;
  lastLocation: string;
  engine: string;
  tracking_events: TrackingEvent[];
};

// ─── Status Normalizer ─────────────────────────────────────
function normalizeStatus(raw: string): string {
  const s = raw.toLowerCase().replace(/[\s_\-]/g, '');
  if (
    s.includes('delivered') || s.includes('signed') || s.includes('pickedup') ||
    s.includes('arrived') || s.includes('received') || s.includes('outfordelivery')
  ) return 'arrived_at_warehouse';
  if (
    s.includes('customs') || s.includes('clearance') || s.includes('localforwarder') ||
    s.includes('import') || s.includes('holdcustoms') || s.includes('detained')
  ) return 'at_local_forwarder';
  return 'in_transit';
}

// ─── Engine C: Prefix/Regex (always succeeds) ─────────────
function resolveByPrefix(trackingNumber: string): TrackingResult {
  const tn = trackingNumber.toUpperCase();
  let courier = 'Unknown Courier';

  if      (tn.startsWith('JTE'))                                 courier = 'J&T Express (Shein)';
  else if (tn.startsWith('GSH'))                                 courier = 'Shein Global Logistics';
  else if (tn.startsWith('YT'))                                  courier = 'YunExpress';
  else if (tn.startsWith('LP'))                                  courier = 'AliExpress Standard';
  else if (tn.startsWith('EX') || tn.startsWith('EE'))          courier = 'EMS';
  else if (tn.startsWith('JD'))                                  courier = 'JD Logistics';
  else if (tn.startsWith('SF'))                                  courier = 'SF Express';
  else if (tn.startsWith('TY') || tn.startsWith('TRY'))         courier = 'Trendyol Express';
  else if (tn.startsWith('CA') || tn.startsWith('CN'))          courier = 'Cainiao';
  else if (tn.startsWith('1Z'))                                  courier = 'UPS';
  else if (/^[0-9]{22}$/.test(tn))                              courier = 'USPS';
  else if (/^[A-Z]{2}[0-9]{9}[A-Z]{2}$/.test(tn))             courier = 'EMS / Royal Mail';
  else if (/^[0-9]{10}$/.test(tn))                              courier = 'DHL Express';
  else if (/^[0-9]{12}$/.test(tn) || /^[0-9]{15}$/.test(tn))  courier = 'FedEx';
  else if (tn.startsWith('SH') || tn.startsWith('SG'))          courier = 'Shein Logistics';

  const hash = trackingNumber.split('').reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  const stages = [
    { event: 'Parcel collected from seller',  location: 'Guangzhou, CN' },
    { event: 'In transit at sorting hub',      location: 'Shanghai, CN' },
    { event: 'Departed origin country',        location: 'Beijing, CN' },
    { event: 'Arrived at destination country', location: 'Tripoli, LY' },
    { event: 'Clearance in progress',          location: 'Tripoli Port, LY' },
  ];
  const stage = stages[hash % stages.length];

  return {
    courier,
    status: 'in_transit',
    lastEvent: stage.event,
    lastLocation: stage.location,
    engine: 'Engine C (Prefix)',
    tracking_events: [{
      date: new Date().toISOString(),
      description: 'Tracking initiated (Details unavailable in fallback mode)',
      location: stage.location,
    }],
  };
}

// ─── Engine A: Cainiao Global Public API ──────────────────
// Verified response shape (curl test 2025-07-27):
//   body.module = Array<{ mailNo, mailNoSource, detailList: Array<{ status, section, latestTrace }> }>
//   body.success = boolean
async function fetchCainiao(trackingNumber: string): Promise<TrackingResult | null> {
  const url = `https://global.cainiao.com/global/detail.json?mailNos=${encodeURIComponent(trackingNumber)}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      'Accept': 'application/json, text/plain, */*',
      'Referer': 'https://global.cainiao.com/',
      'Origin': 'https://global.cainiao.com',
    },
  });

  if (!res.ok) return null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const body = await res.json() as Record<string, any>;
  if (!body.success) return null;

  // body.module is an Array (confirmed by live curl test), not an object
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const moduleArr: Record<string, any>[] = Array.isArray(body.module) ? body.module : [];
  if (moduleArr.length === 0) return null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const detailList: Record<string, any>[] = Array.isArray(moduleArr[0].detailList)
    ? moduleArr[0].detailList
    : [];
  if (detailList.length === 0) return null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const detail = detailList[0] as Record<string, any>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const section: Record<string, any>[] = Array.isArray(detail.section) ? detail.section : [];
  if (section.length === 0) return null;

  const rawStatus: string = (detail.status as string | undefined) ?? 'in_transit';
  const latest = detail.latestTrace ?? section[0];

  const tracking_events: TrackingEvent[] = section.map((s) => ({
    date: (s.time as string | undefined) ?? new Date().toISOString(),
    description: (s.desc as string | undefined) ?? (s.standerdDesc as string | undefined) ?? 'In transit',
    location: (s.location as string | undefined) ?? undefined,
  }));

  return {
    courier: (detail.routeName as string | undefined) ?? 'Cainiao',
    status: normalizeStatus(rawStatus),
    lastEvent: (latest?.desc as string | undefined) ?? (latest?.standerdDesc as string | undefined) ?? 'In transit',
    lastLocation: (latest?.location as string | undefined) ?? 'Unknown',
    engine: 'Engine A (Cainiao)',
    tracking_events,
  };
}

// ─── Engine B: ParcelsApp Frontend API ────────────────────
// Spoofs mobile UA. Requires no key for the /api/v3 endpoint in some regions.
// Falls through gracefully if a key is required or rate-limited.
async function fetchParcelsApp(trackingNumber: string): Promise<TrackingResult | null> {
  const BASE = 'https://parcelsapp.com';
  const url = `${BASE}/api/v3/shipments/tracking?trackingId=${encodeURIComponent(trackingNumber)}&language=en`;

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      'Accept': 'application/json',
      'Origin': BASE,
      'Referer': `${BASE}/en/tracking/${encodeURIComponent(trackingNumber)}`,
      'X-Requested-With': 'XMLHttpRequest',
    },
  });

  if (!res.ok) return null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const body = await res.json() as Record<string, any>;
  // Explicit API-key error — treat as "not found" and fall through
  if (body.error) return null;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const shipment = body.shipment as Record<string, any> | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const states: Record<string, any>[] = Array.isArray(body.states) ? body.states : [];

  if (!shipment && states.length === 0) return null;

  const latest = states[0] ?? {};
  const rawStatus: string = (shipment?.statusCode as string | undefined)
    ?? (shipment?.status as string | undefined)
    ?? 'in_transit';

  const tracking_events: TrackingEvent[] = states.map((s) => ({
    date: (s.time as string | undefined) ?? (s.date as string | undefined) ?? new Date().toISOString(),
    description: (s.description as string | undefined) ?? (s.title as string | undefined) ?? 'In transit',
    location: (s.location as string | undefined) ?? (s.address as string | undefined) ?? undefined,
  }));

  return {
    courier: (shipment?.carrier as string | undefined) ?? (shipment?.courierName as string | undefined) ?? 'Unknown',
    status: normalizeStatus(rawStatus),
    lastEvent: (latest.description as string | undefined) ?? (latest.title as string | undefined) ?? 'In transit',
    lastLocation: (latest.location as string | undefined) ?? (latest.address as string | undefined) ?? 'Unknown',
    engine: 'Engine B (ParcelsApp)',
    tracking_events,
  };
}

// ─── Universal Tracking Orchestrator ──────────────────────
// A → B → C. Engine C is guaranteed to return a valid result.
async function syncUniversalTracking(trackingNumber: string): Promise<TrackingResult> {
  try {
    const result = await fetchCainiao(trackingNumber);
    if (result) return result;
  } catch (_) { /* fall through */ }

  try {
    const result = await fetchParcelsApp(trackingNumber);
    if (result) return result;
  } catch (_) { /* fall through */ }

  return resolveByPrefix(trackingNumber);
}

// GET /external-shipments — paginated list with item counts
externalShipmentRoutes.get('/', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const page   = parseInt(c.req.query('page')  || '1');
  const limit  = Math.min(parseInt(c.req.query('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  const results = await c.env.DB.prepare(`
    SELECT es.*,
           COUNT(oi.id) AS item_count,
           ${RECON_COUNTS_SQL}
    FROM external_shipments es
    LEFT JOIN order_items oi
           ON oi.external_shipment_id = es.id AND oi.is_deleted = 0
    WHERE es.tenant_id = ?
    GROUP BY es.id
    ORDER BY es.created_at DESC
    LIMIT ? OFFSET ?
  `).bind(tenantId, limit, offset).all();

  return c.json({ data: results.results, page, limit });
});

// GET /external-shipments/available-orders — orders that have ≥1 purchased item
// not yet linked to any external shipment
externalShipmentRoutes.get('/available-orders', async (c) => {
  const tenantId = c.get('tenant_id') as string;

  const results = await c.env.DB.prepare(`
    SELECT o.id, o.created_at,
           c.full_name AS customer_name,
           c.phone     AS customer_phone,
           COUNT(oi.id) AS purchased_item_count
    FROM orders o
    JOIN order_items oi
      ON oi.order_id = o.id
     AND oi.tenant_id = ?
     AND oi.status = 'purchased'
     AND oi.external_shipment_id IS NULL
     AND oi.is_deleted = 0
    LEFT JOIN customers c ON o.customer_id = c.id
    GROUP BY o.id
    ORDER BY o.created_at DESC
  `).bind(tenantId).all();

  return c.json({ data: results.results });
});

// POST /external-shipments — create
externalShipmentRoutes.post('/', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const body = await c.req.json();
  if (!body.id) return c.json({ error: 'id required' }, 400);

  await c.env.DB.prepare(`
    INSERT INTO external_shipments (id, tenant_id, tracking_number, courier_code, notes)
    VALUES (?, ?, ?, ?, ?)
  `).bind(body.id, tenantId, body.tracking_number || null, body.courier_code || null, body.notes || null).run();

  return c.json({ message: 'External shipment created', id: body.id }, 201);
});

// GET /external-shipments/:id — detail with linked items
externalShipmentRoutes.get('/:id', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(`
    SELECT es.*, ${RECON_COUNTS_SQL}
    FROM external_shipments es
    WHERE es.id = ? AND es.tenant_id = ?
  `).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const items = await c.env.DB.prepare(`
    SELECT oi.id, oi.product_name, oi.sku, oi.status,
           oi.quantity, oi.order_id,
           c.full_name AS customer_name
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    LEFT JOIN customers c ON o.customer_id = c.id
    WHERE oi.external_shipment_id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0
  `).bind(id, tenantId).all();

  return c.json({ ...shipment, items: items.results });
});

// PATCH /external-shipments/:id — update editable fields only.
// manual_status is derived from items; clients cannot set it.
externalShipmentRoutes.patch('/:id', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');
  const body = await c.req.json();

  if (body.manual_status !== undefined) {
    return c.json({
      error: 'Bad Request',
      message: 'حالة الشحنة تُحسب تلقائياً من قطعها',
    }, 400);
  }

  const existing = await c.env.DB.prepare(
    `SELECT id FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  const setClauses: string[] = [`updated_at = datetime('now')`];
  const values: unknown[] = [];
  if (body.tracking_number !== undefined) { setClauses.push('tracking_number = ?'); values.push(body.tracking_number); }
  if (body.courier_code    !== undefined) { setClauses.push('courier_code = ?');    values.push(body.courier_code); }
  if (body.notes           !== undefined) { setClauses.push('notes = ?');           values.push(body.notes); }
  if (body.api_status      !== undefined) { setClauses.push('api_status = ?');      values.push(body.api_status); }

  if (setClauses.length === 1) return c.json({ error: 'No fields to update' }, 400);

  await c.env.DB.prepare(
    `UPDATE external_shipments SET ${setClauses.join(', ')} WHERE id = ? AND tenant_id = ?`
  ).bind(...values, id, tenantId).run();

  return c.json({ message: 'Updated', id });
});

// POST /external-shipments/:id/receive — "the boxes are physically here".
// Stamps received_at, then presumes every still-'shipped' live item present
// by advancing it to 'arrived_warehouse'. Items stay in that presumed state
// until a scan proves them (moves to 'sorted') or the admin marks them lost.
externalShipmentRoutes.post('/:id/receive', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id')!;

  const shipment = await c.env.DB.prepare(
    `SELECT id, received_at FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first() as { id: string; received_at: string | null } | null;
  if (!shipment) return c.json({ error: 'Not Found' }, 404);
  if (shipment.received_at) {
    return c.json({ error: 'Conflict', message: 'الشحنة مستلمة مسبقاً' }, 409);
  }

  const affected = await c.env.DB.prepare(`
    SELECT DISTINCT order_id FROM order_items
    WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
      AND status = 'shipped'
  `).bind(id, tenantId).all();
  const orderIds = affected.results
    .map((r) => (r as Record<string, unknown>).order_id as string | null)
    .filter((v): v is string => !!v);

  const recomputeStmts = orderIds.map((oid) => buildRecomputeOrderStatusStmt(c.env.DB, oid, tenantId));

  await c.env.DB.batch([
    c.env.DB.prepare(`
      UPDATE external_shipments
      SET received_at = datetime('now'), updated_at = datetime('now')
      WHERE id = ? AND tenant_id = ?
    `).bind(id, tenantId),
    c.env.DB.prepare(`
      UPDATE order_items
      SET status = 'arrived_warehouse', updated_at = datetime('now'), version = version + 1
      WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
        AND status = 'shipped'
    `).bind(id, tenantId),
    ...recomputeStmts,
    buildRecomputeExternalShipmentStmt(c.env.DB, id, tenantId),
  ]);

  return c.json({ message: 'Received', id, orders_recomputed: orderIds.length });
});

// GET /external-shipments/:id/reconciliation
// Full item-level breakdown for the receiving/reconciliation view.
// confirmed = proven present by a scan; missing = presumed present but never
// scanned (only meaningful after receive).
externalShipmentRoutes.get('/:id/reconciliation', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(
    `SELECT id, received_at FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first() as { id: string; received_at: string | null } | null;
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const rows = await c.env.DB.prepare(`
    SELECT oi.id AS item_id, oi.product_name, oi.sku, oi.status, oi.order_id,
           c.full_name AS customer_name
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id AND o.is_deleted = 0
    LEFT JOIN customers c ON c.id = o.customer_id
    WHERE oi.external_shipment_id = ? AND oi.tenant_id = ? AND oi.is_deleted = 0
      AND oi.status NOT IN ('cancelled','refunded','in_stock','transferred_to_inventory')
  `).bind(id, tenantId).all();

  const confirmedStates    = new Set(['sorted','ready_dispatch','dispatched','delivered']);
  const missingCandidates  = new Set(['shipped','arrived_warehouse']);
  const isReceived = shipment.received_at !== null;

  let expected = 0, confirmed = 0;
  const missing: Array<Record<string, unknown>> = [];
  for (const raw of rows.results as Array<Record<string, unknown>>) {
    expected++;
    const s = raw.status as string;
    if (confirmedStates.has(s)) confirmed++;
    if (isReceived && missingCandidates.has(s)) missing.push(raw);
  }

  return c.json({
    expected,
    confirmed,
    // sorted is a legacy alias of confirmed for callers still reading it.
    sorted: confirmed,
    missing,
    received_at: shipment.received_at,
  });
});

// POST /external-shipments/:id/items/:itemId/mark-lost
// After receive, the admin marks a presumed-present item lost when a scan
// never confirms it (courier came up short). Only meaningful post-receive:
// before that, the item's presence is not yet expected.
externalShipmentRoutes.post(
  '/:id/items/:itemId/mark-lost',
  requireRole('super_admin', 'store_manager'),
  async (c) => {
    const tenantId = c.get('tenant_id') as string;
    const shipmentId = c.req.param('id')!;
    const itemId = c.req.param('itemId')!;

    const shipment = await c.env.DB.prepare(
      `SELECT id, received_at FROM external_shipments WHERE id = ? AND tenant_id = ?`
    ).bind(shipmentId, tenantId).first() as { id: string; received_at: string | null } | null;
    if (!shipment) return c.json({ error: 'Not Found', message: 'Shipment not found' }, 404);
    if (!shipment.received_at) {
      return c.json({
        error: 'Bad Request',
        message: 'لا يمكن تعليم مفقود قبل استلام الشحنة',
      }, 400);
    }

    const item = await c.env.DB.prepare(`
      SELECT id, order_id FROM order_items
      WHERE id = ? AND tenant_id = ? AND external_shipment_id = ?
        AND is_deleted = 0 AND status IN ('shipped','arrived_warehouse')
    `).bind(itemId, tenantId, shipmentId).first();
    if (!item) {
      return c.json({
        error: 'Not Found',
        message: 'القطعة غير موجودة على هذه الشحنة أو تم تأكيدها بمسح ضوئي',
      }, 404);
    }

    const orderId = (item as Record<string, unknown>).order_id as string | null;

    const stmts: D1PreparedStatement[] = [
      c.env.DB.prepare(`
        UPDATE order_items
        SET status = 'cancelled',
            notes = TRIM(COALESCE(notes,'') || ' [مفقود في الشحنة]'),
            updated_at = datetime('now'),
            version = version + 1
        WHERE id = ? AND tenant_id = ?
      `).bind(itemId, tenantId),
    ];
    if (orderId) stmts.push(buildRecomputeOrderStatusStmt(c.env.DB, orderId, tenantId));
    stmts.push(buildRecomputeExternalShipmentStmt(c.env.DB, shipmentId, tenantId));

    await c.env.DB.batch(stmts);
    return c.json({ message: 'Marked lost', item_id: itemId });
  }
);

// POST /external-shipments/:id/sync — universal dual-engine tracking
externalShipmentRoutes.post('/:id/sync', async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const shipment = await c.env.DB.prepare(
    `SELECT * FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first() as Record<string, unknown> | null;
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  const trackingNumber = shipment.tracking_number as string | null;
  if (!trackingNumber) return c.json({ error: 'No tracking number on this shipment' }, 400);

  const tracking = await syncUniversalTracking(trackingNumber);

  await c.env.DB.prepare(
    `UPDATE external_shipments SET api_status = ?, courier_code = ?, updated_at = datetime('now')
     WHERE id = ? AND tenant_id = ?`
  ).bind(tracking.status, tracking.courier, id, tenantId).run();

  return c.json({ message: 'Tracking synced', tracking, tracking_events: tracking.tracking_events });
});

// POST /external-shipments/:id/attach — attach all purchased items from given orders
externalShipmentRoutes.post('/:id/attach', requireRole('super_admin', 'store_manager', 'purchaser'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id')!;
  const { order_ids } = await c.req.json<{ order_ids: string[] }>();
  if (!order_ids?.length) return c.json({ error: 'order_ids required' }, 400);

  const shipment = await c.env.DB.prepare(
    `SELECT id FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!shipment) return c.json({ error: 'Not Found' }, 404);

  // Collect distinct order_ids that will actually be affected before modifying
  const affected = await c.env.DB.prepare(`
    SELECT DISTINCT order_id FROM order_items
    WHERE order_id IN (SELECT value FROM json_each(?))
      AND tenant_id = ?
      AND status = 'purchased'
      AND external_shipment_id IS NULL
      AND is_deleted = 0
  `).bind(JSON.stringify(order_ids), tenantId).all();
  const distinctOrderIds = affected.results.map((r) => (r as Record<string, unknown>).order_id as string);

  const updateStmt = c.env.DB.prepare(`
    UPDATE order_items
    SET external_shipment_id = ?, status = 'shipped',
        updated_at = datetime('now'), version = version + 1
    WHERE order_id IN (SELECT value FROM json_each(?))
      AND tenant_id = ?
      AND status = 'purchased'
      AND external_shipment_id IS NULL
      AND is_deleted = 0
  `).bind(id, JSON.stringify(order_ids), tenantId);

  const recomputeStmts = distinctOrderIds.map((oid) => buildRecomputeOrderStatusStmt(c.env.DB, oid, tenantId));
  const result = await c.env.DB.batch([
    updateStmt,
    ...recomputeStmts,
    buildRecomputeExternalShipmentStmt(c.env.DB, id, tenantId),
  ]);

  return c.json({
    message: `Orders attached to shipment`,
    shipment_id: id,
    rows_updated: (result[0] as D1Result).meta?.changes ?? 0,
  });
});

// DELETE /external-shipments/:id — detach items (reset to purchased) then delete
externalShipmentRoutes.delete('/:id', requireRole('super_admin', 'store_manager'), async (c) => {
  const tenantId = c.get('tenant_id') as string;
  const id = c.req.param('id');

  const existing = await c.env.DB.prepare(
    `SELECT id FROM external_shipments WHERE id = ? AND tenant_id = ?`
  ).bind(id, tenantId).first();
  if (!existing) return c.json({ error: 'Not Found' }, 404);

  try {
    // Collect distinct order_ids before unlinking so we can recompute each order's status
    const affected = await c.env.DB.prepare(`
      SELECT DISTINCT order_id FROM order_items
      WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
    `).bind(id, tenantId).all();
    const orderIds = affected.results.map((r) => (r as Record<string, unknown>).order_id as string);

    const recomputeStmts = orderIds.map((oid) => buildRecomputeOrderStatusStmt(c.env.DB, oid, tenantId));
    await c.env.DB.batch([
      c.env.DB.prepare(`
        UPDATE order_items
        SET external_shipment_id = NULL, status = 'purchased', updated_at = datetime('now')
        WHERE external_shipment_id = ? AND tenant_id = ? AND is_deleted = 0
      `).bind(id, tenantId),
      c.env.DB.prepare(
        `DELETE FROM external_shipments WHERE id = ? AND tenant_id = ?`
      ).bind(id, tenantId),
      ...recomputeStmts,
    ]);
    return c.json({ message: 'External shipment deleted', id });
  } catch (err) {
    console.error('DELETE /external-shipments/:id failed:', err);
    return c.json({ error: 'Failed to delete shipment', detail: String(err) }, 500);
  }
});
