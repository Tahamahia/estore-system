import { describe, it, expect, beforeEach } from 'vitest';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Hono } from 'hono';
import type { AppEnv } from '../src/types';
import { settlementRoutes } from '../src/routes/settlements';
import { orderRoutes } from '../src/routes/orders';
import { analyticsRoutes } from '../src/routes/analytics';

/**
 * Settlement accounting — runs the real route handlers against an in-memory
 * SQLite loaded from schema.sql, through a minimal D1 shim.
 */

// node:sqlite is loaded via require so Vite does not try to bundle it.
const { DatabaseSync } = createRequire(import.meta.url)('node:sqlite');

type Row = Record<string, unknown>;
const isRead = (sql: string) => /^\s*(SELECT|WITH)\b/i.test(sql);

function d1(db: any) {
  class Stmt {
    constructor(readonly sql: string, readonly params: unknown[] = []) {}
    bind(...p: unknown[]) { return new Stmt(this.sql, p); }
    async all() { return this.exec(); }
    async first<T = Row>() { return (db.prepare(this.sql).get(...this.params) ?? null) as T | null; }
    async run() { return this.exec(); }
    exec() {
      const st = db.prepare(this.sql);
      if (isRead(this.sql)) return { results: st.all(...this.params) as Row[], meta: { changes: 0 } };
      const r = st.run(...this.params);
      return { results: [] as Row[], meta: { changes: Number(r.changes) } };
    }
  }
  return {
    prepare: (sql: string) => new Stmt(sql),
    async batch(stmts: Stmt[]) {
      db.exec('BEGIN');
      try {
        const out = stmts.map((s) => s.exec());
        db.exec('COMMIT');
        return out;
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },
  };
}

const T = 't1';
let db: any;
let app: Hono<AppEnv>;

function call(method: string, path: string, body?: unknown, role = 'super_admin') {
  return app.request(path, {
    method,
    headers: { 'Content-Type': 'application/json', 'X-Role': role },
    body: body === undefined ? undefined : JSON.stringify(body),
  }, { DB: d1(db) } as any);
}

function insertOrder(o: Row) {
  db.prepare(
    `INSERT INTO orders (id, tenant_id, customer_id, order_type, status, total_sale_price_lyd, total_cost_usd,
                         deposit_amount, cash_collected, cash_collected_at, internal_shipment_id)
     VALUES (?, ?, 'c1', ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    o.id as string, T, (o.order_type as string) ?? 'individual_items', (o.status as string) ?? 'delivered',
    (o.sale ?? null) as number | null, (o.cost ?? null) as number | null,
    (o.deposit ?? 0) as number, (o.collected ?? 0) as number,
    (o.collected_at ?? null) as string | null, (o.shipment ?? null) as string | null,
  );
}

function insertItem(i: Row) {
  db.prepare(
    `INSERT INTO order_items (id, tenant_id, order_id, product_name, quantity, unit_price_local,
                              cost_usd, weight, shipping_rate_per_kg, status, lost_at)
     VALUES (?, ?, ?, 'p', ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    i.id as string, T, (i.order_id ?? null) as string | null, (i.qty ?? 1) as number,
    (i.price ?? 0) as number, (i.cost ?? 0) as number, (i.weight ?? 0) as number,
    (i.rate ?? 0) as number, (i.status as string) ?? 'delivered', (i.lost_at ?? null) as string | null,
  );
}

beforeEach(() => {
  db = new DatabaseSync(':memory:', { enableForeignKeyConstraints: false });
  db.exec(readFileSync(resolve(__dirname, '../src/db/schema.sql'), 'utf8'));
  db.prepare(`INSERT INTO customers (id, tenant_id, full_name, phone, city, area) VALUES ('c1', ?, 'Mona', '0911', 'Tripoli', 'Hay')`).run(T);

  app = new Hono<AppEnv>();
  app.use('*', async (c, next) => {
    c.set('tenant_id', T);
    c.set('user_id', 'u1');
    c.set('user_role', c.req.header('X-Role') ?? 'super_admin');
    await next();
  });
  app.route('/settlements', settlementRoutes);
  app.route('/orders', orderRoutes);
  app.route('/analytics', analyticsRoutes);

  // Hand-checked scenario (rate 5).
  // o1: full_cart, sale 200 / cost 26 $, deposit 50, collected 150 (tracked).
  insertOrder({ id: 'o1', order_type: 'full_cart', sale: 200, cost: 26, deposit: 50, collected: 150, collected_at: '2026-10-01' });
  // o2: items, sale 150, cost 20 + 1kg × 3 = 23 $, collected 140 (10 door discount).
  insertOrder({ id: 'o2', collected: 140, collected_at: '2026-10-01' });
  insertItem({ id: 'i2', order_id: 'o2', price: 150, cost: 20, weight: 1, rate: 3 });
  // o3: items, sale 250 + 150 = 400, cost 30 + (20 + 2kg × 4) = 58 $, fully
  // paid by deposit; delivered before cash tracking (cash_collected_at NULL).
  insertOrder({ id: 'o3', deposit: 400 });
  insertItem({ id: 'i3a', order_id: 'o3', price: 250, cost: 30 });
  insertItem({ id: 'i3b', order_id: 'o3', price: 150, cost: 20, weight: 2, rate: 4 });
  // Lost piece on o3: cancelled, excluded from o3's sale and cost, expensed via write-off.
  insertItem({ id: 'i3lost', order_id: 'o3', price: 50, cost: 10, status: 'cancelled', lost_at: '2026-09-20' });
  // Unsold instant-stock piece.
  insertItem({ id: 'stock1', order_id: null, cost: 13, status: 'in_stock' });
});

describe('settlement accounting', () => {
  it('reproduces the hand-checked scenario', async () => {
    const res = await call('POST', '/settlements', {
      name: 'October', exchange_rate: 5, order_ids: ['o1', 'o2', 'o3'], write_off: true,
    });
    expect(res.status).toBe(201);
    const s = await res.json() as Row;

    expect(s.total_lyd_collected).toBe(740);
    expect(s.total_sale_lyd).toBe(750);
    expect(s.door_discount_lyd).toBe(10);
    expect(s.total_usd_cost).toBe(107);
    expect(s.write_off_unsold_usd).toBe(13);
    expect(s.write_off_lost_usd).toBe(10);
    expect(s.total_write_off_usd).toBe(23);
    expect(s.net_profit_usd).toBeCloseTo(740 / 5 - 107 - 23); // 18
    expect(s.net_profit_usd).toBeCloseTo(18);
    expect(s.order_count).toBe(3);

    // List and detail agree with the create response.
    const list = (await (await call('GET', '/settlements')).json() as { data: Row[] }).data;
    expect(list[0]).toMatchObject({ total_lyd_collected: 740, door_discount_lyd: 10, write_off_lost_usd: 10, write_off_unsold_usd: 13 });
    const detail = await (await call('GET', `/settlements/${s.id}`)).json() as Row & { orders: Row[] };
    expect(detail.net_profit_usd).toBeCloseTo(18);
    expect(detail.orders.find((o) => o.id === 'o2')).toMatchObject({ actual_lyd: 140, door_discount_lyd: 10 });
  });

  it('expenses lost items even when the write-off box is unchecked', async () => {
    const s = await (await call('POST', '/settlements', {
      name: 'No box', exchange_rate: 5, order_ids: ['o1'],
    })).json() as Row;
    expect(s.write_off_lost_usd).toBe(10);
    expect(s.write_off_unsold_usd).toBe(0);
    const item = db.prepare(`SELECT written_off_settlement_id FROM order_items WHERE id = 'stock1'`).get();
    expect(item.written_off_settlement_id).toBeNull();
  });

  it('books a forfeited deposit as revenue with zero cost', async () => {
    insertOrder({ id: 'oc', status: 'cancelled', deposit: 30 });

    const pending = await (await call('GET', '/orders?deposit_pending=true')).json() as { data: Row[] };
    expect(pending.data.map((o) => o.id)).toEqual(['oc']);

    expect((await call('PATCH', '/orders/o1/deposit', { deposit_status: 'forfeited' })).status).toBe(400);
    expect((await call('PATCH', '/orders/oc/deposit', { deposit_status: 'forfeited' }, 'purchaser')).status).toBe(403);
    expect((await call('PATCH', '/orders/oc/deposit', { deposit_status: 'forfeited' })).status).toBe(200);

    const kept = await (await call('GET', '/orders?deposit_forfeited=true')).json() as { data: Row[] };
    expect(kept.data.map((o) => o.id)).toEqual(['oc']);

    const s = await (await call('POST', '/settlements', {
      name: 'Forfeit', exchange_rate: 5, order_ids: ['o2'], forfeited_order_ids: ['oc'],
    })).json() as Row;
    expect(s.total_lyd_collected).toBe(170);
    expect(s.forfeited_deposits_lyd).toBe(30);
    expect(s.door_discount_lyd).toBe(10);
    expect(s.total_usd_cost).toBe(23);
    expect(s.order_count).toBe(1);
    expect(s.forfeited_order_count).toBe(1);

    // Locked once settled.
    expect((await call('PATCH', '/orders/oc/deposit', { deposit_status: 'refunded' })).status).toBe(409);
  });

  it('rejects ineligible order ids, including unknown ones', async () => {
    const res = await call('POST', '/settlements', { name: 'x', exchange_rate: 5, order_ids: ['o1', 'nope'] });
    expect(res.status).toBe(400);
    expect((await res.json() as Row).invalid_order_ids).toEqual(['nope']);
  });

  it('reports driver debts from short handovers', async () => {
    db.prepare(`INSERT INTO internal_shipments (id, tenant_id, driver_name, cash_handed_over) VALUES ('m1', ?, 'Ali', 280)`).run(T);
    db.prepare(`UPDATE orders SET internal_shipment_id = 'm1' WHERE id IN ('o1', 'o2')`).run();
    const dash = await (await call('GET', '/analytics/dashboard')).json() as { driver_debts: Row[] };
    expect(dash.driver_debts).toEqual([{ driver_name: 'Ali', amount: 10, manifest_count: 1 }]);
  });

  it('serves a price-free label to the sorter only', async () => {
    db.prepare(`INSERT INTO internal_shipments (id, tenant_id, delivery_company, driver_name) VALUES ('m1', ?, 'Fast', 'Ali')`).run(T);
    db.prepare(`UPDATE orders SET internal_shipment_id = 'm1' WHERE id = 'o3'`).run();

    expect((await call('GET', '/orders/o3/label', undefined, 'purchaser')).status).toBe(403);
    const res = await call('GET', '/orders/o3/label', undefined, 'sorter');
    expect(res.status).toBe(200);
    const label = await res.json() as Row;
    expect(label).toMatchObject({ id: 'o3', full_name: 'Mona', item_count: 2, amount_to_collect: 0, delivery_company: 'Fast', driver_name: 'Ali' });
    expect(Object.keys(label).some((k) => /cost|price|sale/.test(k))).toBe(false);

    const o2 = await (await call('GET', '/orders/o1/label', undefined, 'sorter')).json() as Row;
    expect(o2.amount_to_collect).toBe(150);

    expect((await call('GET', '/orders/o3', undefined, 'sorter')).status).toBe(403);
  });
});
