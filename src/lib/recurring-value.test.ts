import { describe, it, expect } from 'vitest';
import { computeRecurringRollup, monthlyCents, effectiveCents } from './recurring-value';

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
