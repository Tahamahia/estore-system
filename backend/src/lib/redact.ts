/**
 * Money-field redaction for roles that must never see prices or cash (the
 * sorter). Matches by key name so a new column like `refund_amount` or
 * `fee_lyd` is stripped without touching this file:
 * cash_*, *price*, *cost*, *amount*, *sale*, *deposit*, *_lyd, *_usd.
 */
const MONEY_KEY = /cash|price|cost|amount|sale|deposit|_lyd$|_usd$/i;

export function isMoneyKey(key: string): boolean {
  return MONEY_KEY.test(key);
}

/** Deep copy of `value` with every money-named key removed, at any depth. */
export function stripMoneyFields<T>(value: T): T {
  if (Array.isArray(value)) return value.map(stripMoneyFields) as T;
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (!isMoneyKey(k)) out[k] = stripMoneyFields(v);
    }
    return out as T;
  }
  return value;
}

/** Strip money fields when the caller's role must not see them. */
export function forRole<T>(role: string | undefined, payload: T): T {
  return role === 'sorter' ? stripMoneyFields(payload) : payload;
}
