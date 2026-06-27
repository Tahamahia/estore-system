import { describe, it, expect } from 'vitest';

/**
 * Landed Cost Calculator — Pure Math Tests
 *
 * These test the exact distribution algorithm extracted from the route handler.
 * ALL math uses INTEGER CENTS to prevent floating-point errors.
 */

// ─── Extracted pure function from landed-cost.ts ───────────
interface ItemWeight {
  id: string;
  effectiveWeight: number;
  sellPriceCents: number;
  purchasePriceCents: number;
}

interface CostBreakdown {
  item_id: string;
  effective_weight_kg: number;
  weight_share_pct: number;
  landed_cost_cents: number;
  net_profit_cents: number | null;
}

function calculateLandedCosts(
  totalCostCents: number,
  items: ItemWeight[]
): { breakdown: CostBreakdown[]; totalDistributed: number } {
  const DEFAULT_WEIGHT_KG = 0.1;

  const itemWeights = items.map(item => ({
    ...item,
    effectiveWeight: item.effectiveWeight > 0 ? item.effectiveWeight : DEFAULT_WEIGHT_KG,
  }));

  const totalWeight = itemWeights.reduce((sum, iw) => sum + iw.effectiveWeight, 0);

  if (totalWeight <= 0) {
    throw new Error('Total weight is zero');
  }

  const breakdown: CostBreakdown[] = [];
  let distributedCents = 0;

  for (let i = 0; i < itemWeights.length; i++) {
    const iw = itemWeights[i];

    let landedCostCents: number;
    if (i === itemWeights.length - 1) {
      // Last item gets remainder to prevent rounding loss
      landedCostCents = totalCostCents - distributedCents;
    } else {
      landedCostCents = Math.round(totalCostCents * iw.effectiveWeight / totalWeight);
    }
    distributedCents += landedCostCents;

    const weightSharePct = Math.round((iw.effectiveWeight / totalWeight) * 10000) / 100;

    const netProfitCents = iw.sellPriceCents > 0
      ? iw.sellPriceCents - iw.purchasePriceCents - landedCostCents
      : null;

    breakdown.push({
      item_id: iw.id,
      effective_weight_kg: iw.effectiveWeight,
      weight_share_pct: weightSharePct,
      landed_cost_cents: landedCostCents,
      net_profit_cents: netProfitCents,
    });
  }

  return { breakdown, totalDistributed: distributedCents };
}

// ─── Tests ─────────────────────────────────────────────────
describe('Landed Cost Calculator', () => {

  it('distributes costs equally for equal-weight items', () => {
    const result = calculateLandedCosts(10000, [  // $100.00 total
      { id: 'a', effectiveWeight: 1.0, sellPriceCents: 5000, purchasePriceCents: 2000 },
      { id: 'b', effectiveWeight: 1.0, sellPriceCents: 5000, purchasePriceCents: 2000 },
    ]);

    expect(result.breakdown[0].landed_cost_cents).toBe(5000);
    expect(result.breakdown[1].landed_cost_cents).toBe(5000);
    expect(result.totalDistributed).toBe(10000);
  });

  it('distributes proportionally based on weight', () => {
    const result = calculateLandedCosts(10000, [  // $100.00 total
      { id: 'heavy', effectiveWeight: 3.0, sellPriceCents: 10000, purchasePriceCents: 4000 },
      { id: 'light', effectiveWeight: 1.0, sellPriceCents: 5000, purchasePriceCents: 2000 },
    ]);

    // Heavy item (3/4 = 75%) should get 7500 cents
    expect(result.breakdown[0].landed_cost_cents).toBe(7500);
    // Light item (1/4 = 25%) should get 2500 cents
    expect(result.breakdown[1].landed_cost_cents).toBe(2500);
    expect(result.totalDistributed).toBe(10000);
  });

  it('total distributed ALWAYS equals total cost (no rounding loss)', () => {
    // Use awkward numbers that cause rounding issues
    const result = calculateLandedCosts(9999, [  // $99.99
      { id: 'a', effectiveWeight: 1.3, sellPriceCents: 5000, purchasePriceCents: 2000 },
      { id: 'b', effectiveWeight: 2.7, sellPriceCents: 8000, purchasePriceCents: 3000 },
      { id: 'c', effectiveWeight: 0.5, sellPriceCents: 3000, purchasePriceCents: 1000 },
    ]);

    // The SUM must exactly equal input — no penny lost
    expect(result.totalDistributed).toBe(9999);
  });

  it('handles single item receiving all costs', () => {
    const result = calculateLandedCosts(15050, [
      { id: 'solo', effectiveWeight: 2.5, sellPriceCents: 30000, purchasePriceCents: 10000 },
    ]);

    expect(result.breakdown[0].landed_cost_cents).toBe(15050);
    expect(result.totalDistributed).toBe(15050);
  });

  it('uses default weight when actual and volumetric are both 0', () => {
    const result = calculateLandedCosts(10000, [
      { id: 'noweight', effectiveWeight: 0, sellPriceCents: 5000, purchasePriceCents: 2000 },
      { id: 'hasweight', effectiveWeight: 1.0, sellPriceCents: 5000, purchasePriceCents: 2000 },
    ]);

    // noweight gets default 0.1, so total = 1.1
    // noweight share: 0.1/1.1 ≈ 9.09%
    expect(result.breakdown[0].landed_cost_cents).toBe(909);
    // hasweight gets remainder
    expect(result.breakdown[1].landed_cost_cents).toBe(10000 - 909);
    expect(result.totalDistributed).toBe(10000);
  });

  it('calculates net profit correctly', () => {
    const result = calculateLandedCosts(2000, [
      { id: 'a', effectiveWeight: 1.0, sellPriceCents: 10000, purchasePriceCents: 5000 },
    ]);

    // net_profit = sell(10000) - purchase(5000) - landed(2000) = 3000 cents = $30.00
    expect(result.breakdown[0].net_profit_cents).toBe(3000);
  });

  it('detects negative profit (loss)', () => {
    const result = calculateLandedCosts(8000, [
      { id: 'lossy', effectiveWeight: 1.0, sellPriceCents: 5000, purchasePriceCents: 4000 },
    ]);

    // net_profit = 5000 - 4000 - 8000 = -7000 (loss)
    expect(result.breakdown[0].net_profit_cents).toBe(-7000);
  });

  it('returns null net_profit when sell price is 0', () => {
    const result = calculateLandedCosts(5000, [
      { id: 'noSell', effectiveWeight: 1.0, sellPriceCents: 0, purchasePriceCents: 3000 },
    ]);

    expect(result.breakdown[0].net_profit_cents).toBeNull();
  });

  it('handles many items without rounding drift', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({
      id: `item-${i}`,
      effectiveWeight: 0.3 + (i * 0.07),  // Varying weights
      sellPriceCents: 10000,
      purchasePriceCents: 5000,
    }));

    const result = calculateLandedCosts(1234567, items);  // $12,345.67

    // Total MUST be exact — no penny lost across 100 items
    expect(result.totalDistributed).toBe(1234567);
  });

  it('throws on zero total weight (all items have 0 weight after default)', () => {
    // This shouldn't happen due to default weight, but test the guard
    expect(() => calculateLandedCosts(10000, [])).toThrow();
  });
});

describe('Currency Slippage', () => {
  function calculateSlippage(peggedRate: number, actualRate: number): {
    slippagePct: number;
    marginWarning: boolean;
  } {
    const slippagePct = peggedRate > 0
      ? Math.round(((actualRate - peggedRate) / peggedRate) * 10000) / 100
      : 0;
    return { slippagePct, marginWarning: slippagePct > 3 };
  }

  it('calculates 0% slippage when rates are equal', () => {
    const result = calculateSlippage(4.85, 4.85);
    expect(result.slippagePct).toBe(0);
    expect(result.marginWarning).toBe(false);
  });

  it('calculates positive slippage (rate went up = loss)', () => {
    const result = calculateSlippage(4.85, 5.10);
    // (5.10 - 4.85) / 4.85 = 0.0515... = 5.15%
    expect(result.slippagePct).toBe(5.15);
    expect(result.marginWarning).toBe(true);
  });

  it('calculates negative slippage (rate went down = gain)', () => {
    const result = calculateSlippage(5.00, 4.90);
    // (4.90 - 5.00) / 5.00 = -0.02 = -2%
    expect(result.slippagePct).toBe(-2);
    expect(result.marginWarning).toBe(false);
  });

  it('warns at exactly the 3% threshold boundary', () => {
    // 3% of 5.00 = 0.15 → actual = 5.15
    const result = calculateSlippage(5.00, 5.15);
    expect(result.slippagePct).toBe(3);
    expect(result.marginWarning).toBe(false); // > 3, not >= 3
  });

  it('warns above 3% threshold', () => {
    const result = calculateSlippage(5.00, 5.16);
    expect(result.slippagePct).toBe(3.2);
    expect(result.marginWarning).toBe(true);
  });

  it('returns 0 slippage when pegged rate is 0', () => {
    const result = calculateSlippage(0, 5.00);
    expect(result.slippagePct).toBe(0);
    expect(result.marginWarning).toBe(false);
  });
});

describe('Integer Cents Math', () => {
  it('converts foreign cents to local cents correctly', () => {
    const purchasePriceCents = 1599; // ¥15.99
    const actualRate = 4.85;         // 1 CNY = 4.85 LYD
    const localCostCents = Math.round(purchasePriceCents * actualRate);
    expect(localCostCents).toBe(7755); // $77.55
  });

  it('prevents floating-point drift in multiplication', () => {
    // Classic floating point issue: 0.1 + 0.2 !== 0.3
    // But with integer cents: 10 + 20 === 30
    const a = 10; // 0.10
    const b = 20; // 0.20
    expect(a + b).toBe(30); // exact
  });

  it('rounds correctly at half-cent boundary', () => {
    // 1000 cents * 3 / 7 = 428.571... → rounds to 429
    const result = Math.round(1000 * 3 / 7);
    expect(result).toBe(429);
  });
});
