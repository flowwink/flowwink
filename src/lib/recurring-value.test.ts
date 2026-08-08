import { describe, it, expect } from 'vitest';
import {
  computeRecurringRollup, monthlyCents, effectiveCents,
  dealHeadline, deriveContractBilling,
} from './recurring-value';

// Amounts in minor units (cents/öre). 10 000 kr = 1_000_000.
const AI_MONTH = { qty: 1, unit_price_cents: 1_000_000, recurrence: 'month' as const };
const INSTALL = { qty: 1, unit_price_cents: 500_000, recurrence: 'one_time' as const };

describe('the degenerate one-time case stays silent', () => {
  it('a pure one-time quote has no MRR and TCV = face value', () => {
    const r = computeRecurringRollup([INSTALL]);
    expect(r.hasRecurring).toBe(false);
    expect(r.mrrCents).toBe(0);
    expect(r.oneTimeCents).toBe(500_000);
    expect(r.tcvCents).toBe(500_000);
  });

  it('treats an unset recurrence as one-time', () => {
    const r = computeRecurringRollup([{ qty: 2, unit_price_cents: 100_000 }]);
    expect(r.hasRecurring).toBe(false);
    expect(r.oneTimeCents).toBe(200_000);
  });
});

describe("Magnus's case: 10 000/mån, 36 mån, + 5 000 engångsinstallation", () => {
  const rollup = computeRecurringRollup([AI_MONTH, INSTALL], 36);

  it('MRR is the monthly recurring only', () => expect(rollup.mrrCents).toBe(1_000_000));
  it('ARR is MRR × 12', () => expect(rollup.arrCents).toBe(12_000_000));
  it('one-time is the install fee only', () => expect(rollup.oneTimeCents).toBe(500_000));
  it('TCV = one-time + monthly × term', () =>
    expect(rollup.tcvCents).toBe(500_000 + 1_000_000 * 36)); // 36_500_000
  it('has recurring and the term is present', () => {
    expect(rollup.hasRecurring).toBe(true);
    expect(rollup.termMissing).toBe(false);
  });
});

describe('cadence normalisation', () => {
  it('a yearly line contributes 1/12 to MRR', () => {
    expect(monthlyCents({ qty: 1, unit_price_cents: 1_200_000, recurrence: 'year' })).toBe(100_000);
  });

  it('a yearly line’s TCV uses the term in months', () => {
    // 1 200 000/år over 24 months = 100 000/mo × 24 = 2 400 000
    const r = computeRecurringRollup([{ qty: 1, unit_price_cents: 1_200_000, recurrence: 'year' }], 24);
    expect(r.arrCents).toBe(1_200_000);
    expect(r.tcvCents).toBe(2_400_000);
  });

  it('applies quantity and discount to the effective amount', () => {
    expect(effectiveCents({ qty: 3, unit_price_cents: 100_000, discount_pct: 10 })).toBe(270_000);
  });
});

describe('the deal headline carries the dimension (step 3)', () => {
  const AI = { type: 'recurring' as const, billing_interval: 'month' as const, default_term_months: 36 };

  it('a one-time or product-less deal renders exactly as today', () => {
    expect(dealHeadline(null, 120_000_00, 'arr')).toEqual(
      { cents: 120_000_00, suffix: '', secondaryCents: null, secondarySuffix: '' });
    expect(dealHeadline({ type: 'one_time' }, 500_000, 'tcv').suffix).toBe('');
  });

  it("basis 'arr': 10 000/mån headlines as 120 000 ARR with the period as context", () => {
    const h = dealHeadline(AI, 1_000_000, 'arr');
    expect(h.cents).toBe(12_000_000);
    expect(h.suffix).toBe('ARR');
    expect(h.secondaryCents).toBe(1_000_000);
    expect(h.secondarySuffix).toBe('/mo');
  });

  it("basis 'tcv' uses the product's suggested term (36 mo)", () => {
    const h = dealHeadline(AI, 1_000_000, 'tcv');
    expect(h.cents).toBe(36_000_000);
    expect(h.suffix).toBe('TCV');
  });

  it("basis 'tcv' falls back to ARR when no term exists — never a guess", () => {
    const h = dealHeadline({ ...AI, default_term_months: null }, 1_000_000, 'tcv');
    expect(h.suffix).toBe('ARR');
    expect(h.cents).toBe(12_000_000);
  });

  it("basis 'per_period' keeps today's number, now with its dimension", () => {
    const h = dealHeadline(AI, 1_000_000, 'per_period');
    expect(h.cents).toBe(1_000_000);
    expect(h.suffix).toBe('/mo');
  });

  it('a yearly product normalises via months for ARR', () => {
    const h = dealHeadline({ type: 'recurring', billing_interval: 'year' }, 1_200_000, 'arr');
    expect(h.cents).toBe(1_200_000); // 100 000/mo × 12
    expect(h.secondarySuffix).toBe('/yr');
  });
});

describe('the contract inherits the quote billing (step 4)', () => {
  it('a pure one-time quote seeds no recurring billing', () => {
    expect(deriveContractBilling([INSTALL])).toBeNull();
  });

  it('single cadence: bills the per-period sum in that cadence', () => {
    const seed = deriveContractBilling([AI_MONTH, INSTALL]);
    expect(seed).toEqual({ billing_amount_cents: 1_000_000, billing_interval: 'month' });
  });

  it('a yearly-only quote bills yearly, untranslated', () => {
    const seed = deriveContractBilling([{ qty: 1, unit_price_cents: 1_200_000, recurrence: 'year' }]);
    expect(seed).toEqual({ billing_amount_cents: 1_200_000, billing_interval: 'year' });
  });

  it('mixed cadences normalise to monthly — the honest common denominator', () => {
    const seed = deriveContractBilling([
      AI_MONTH,
      { qty: 1, unit_price_cents: 1_200_000, recurrence: 'year' },
    ]);
    expect(seed).toEqual({ billing_amount_cents: 1_100_000, billing_interval: 'month' });
  });

  it('one-time lines never leak into the recurring billing amount', () => {
    const seed = deriveContractBilling([AI_MONTH, { qty: 10, unit_price_cents: 999_999, recurrence: 'one_time' }]);
    expect(seed!.billing_amount_cents).toBe(1_000_000);
  });
});

describe('a term must be known for TCV to be complete', () => {
  it('flags termMissing and understates TCV when no term is set', () => {
    const r = computeRecurringRollup([AI_MONTH]); // no line term, no default
    expect(r.termMissing).toBe(true);
    expect(r.mrrCents).toBe(1_000_000);
    expect(r.tcvCents).toBe(0); // recurring contributes 0 to TCV without a term
  });

  it('a per-line term overrides the quote default', () => {
    const r = computeRecurringRollup([{ ...AI_MONTH, term_months: 12 }], 36);
    expect(r.tcvCents).toBe(1_000_000 * 12);
    expect(r.termMissing).toBe(false);
  });
});
