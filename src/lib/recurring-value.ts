/**
 * Recurring value — the derivations that turn dimensioned quote lines into the
 * named rollups. Pure functions of the line facts; nothing here is ever typed in
 * by a user. See docs/architecture/recurring-value-model.md.
 *
 * A price is (amount, cadence, term). One-time is the degenerate case where
 * cadence = once and term = 1, so MRR = 0 and TCV = the amount — which is why a
 * pure product quote collapses to the plain total and this module stays silent.
 */

export type Recurrence = 'one_time' | 'month' | 'year';

/** The subset of a quote line these derivations need. */
export interface RecurringLineInput {
  qty: number;
  unit_price_cents: number;
  discount_pct?: number | null;
  /** undefined/null is treated as one_time (the degenerate case). */
  recurrence?: Recurrence | null;
  /** per-line binding term; falls back to the quote's default term. */
  term_months?: number | null;
}

export interface RecurringRollup {
  /** Σ effective amount of the one-time lines. */
  oneTimeCents: number;
  /** Monthly recurring revenue — Σ recurring lines normalised to a month. */
  mrrCents: number;
  /** Annual recurring revenue — mrr × 12. */
  arrCents: number;
  /** Total contract value — one-time + Σ(monthly × term) over each line's term. */
  tcvCents: number;
  /** Are there any recurring lines at all? Drives whether the UI shows this. */
  hasRecurring: boolean;
  /** True when a recurring line has no term (line or quote default) — TCV is
   *  then understated and the UI should prompt for a binding term. */
  termMissing: boolean;
}

/** qty × unit price × (1 − discount), rounded to whole cents. */
export function effectiveCents(line: RecurringLineInput): number {
  const disc = 1 - (line.discount_pct ?? 0) / 100;
  return Math.round(line.qty * line.unit_price_cents * disc);
}

/** The line's amount expressed per month (0 for one-time). */
export function monthlyCents(line: RecurringLineInput): number {
  const eff = effectiveCents(line);
  switch (line.recurrence) {
    case 'month': return eff;
    case 'year': return Math.round(eff / 12);
    default: return 0; // one_time or unset
  }
}

const isRecurring = (r?: Recurrence | null): r is 'month' | 'year' =>
  r === 'month' || r === 'year';

/**
 * Roll a set of lines up to { one-time, MRR, ARR, TCV }. `defaultTermMonths` is
 * the quote-level binding term used for any recurring line without its own.
 */
export function computeRecurringRollup(
  lines: RecurringLineInput[],
  defaultTermMonths?: number | null,
): RecurringRollup {
  let oneTimeCents = 0;
  let mrrCents = 0;
  let tcvCents = 0;
  let hasRecurring = false;
  let termMissing = false;

  for (const line of lines) {
    if (isRecurring(line.recurrence)) {
      hasRecurring = true;
      const monthly = monthlyCents(line);
      mrrCents += monthly;
      const term = line.term_months ?? defaultTermMonths ?? null;
      if (term == null) termMissing = true;
      tcvCents += monthly * (term ?? 0);
    } else {
      const eff = effectiveCents(line);
      oneTimeCents += eff;
      tcvCents += eff; // a one-time line contributes its face value to TCV
    }
  }

  return {
    oneTimeCents,
    mrrCents,
    arrCents: mrrCents * 12,
    tcvCents,
    hasRecurring,
    termMissing,
  };
}

// ── the deal's headline ─────────────────────────────────────────────────────

/** Which derived figure headlines a recurring deal. Site-configurable
 *  (sales_pipeline.deal_value_basis) — data, not a code branch. */
export type DealValueBasis = 'per_period' | 'arr' | 'tcv';

export interface DealHeadline {
  /** The amount to display. */
  cents: number;
  /** Short dimension label to render after the amount: '/mo', '/yr', 'ARR',
   *  'TCV' — empty for a one-time deal (today's rendering, unchanged). */
  suffix: string;
  /** The per-period price as secondary context when the headline is a rollup
   *  (e.g. headline "120 000 ARR", secondary "10 000/mo"). Null when redundant. */
  secondaryCents: number | null;
  secondarySuffix: string;
}

/** The minimal product facts the headline needs (joined onto the deal). */
export interface DealProductFacts {
  type?: 'one_time' | 'recurring' | null;
  billing_interval?: 'month' | 'year' | null;
  default_term_months?: number | null;
}

const PERIOD_SUFFIX: Record<'month' | 'year', string> = { month: '/mo', year: '/yr' };

/**
 * Derive what a deal's value display should say. `valueCents` is the deal's
 * stored amount — for a product-seeded deal that's the product's per-period
 * price. A one-time deal (or no product) returns the plain amount, exactly as
 * today: the degenerate case stays silent.
 */
export function dealHeadline(
  product: DealProductFacts | null | undefined,
  valueCents: number,
  basis: DealValueBasis,
): DealHeadline {
  if (product?.type !== 'recurring') {
    return { cents: valueCents, suffix: '', secondaryCents: null, secondarySuffix: '' };
  }
  const interval = product.billing_interval ?? 'month';
  const perPeriod = { cents: valueCents, suffix: PERIOD_SUFFIX[interval] };
  const monthly = interval === 'year' ? Math.round(valueCents / 12) : valueCents;

  if (basis === 'arr') {
    return { cents: monthly * 12, suffix: 'ARR', secondaryCents: perPeriod.cents, secondarySuffix: perPeriod.suffix };
  }
  if (basis === 'tcv') {
    const term = product.default_term_months ?? null;
    // Without a term TCV is unknowable — fall back to ARR rather than lie.
    if (term == null) {
      return { cents: monthly * 12, suffix: 'ARR', secondaryCents: perPeriod.cents, secondarySuffix: perPeriod.suffix };
    }
    return { cents: monthly * term, suffix: 'TCV', secondaryCents: perPeriod.cents, secondarySuffix: perPeriod.suffix };
  }
  // per_period — today's number, now carrying its dimension.
  return { cents: perPeriod.cents, suffix: perPeriod.suffix, secondaryCents: null, secondarySuffix: '' };
}

// ── quote → contract inheritance ────────────────────────────────────────────

export interface ContractBillingSeed {
  billing_amount_cents: number;
  billing_interval: 'month' | 'year';
}

/**
 * What the agreement should bill, derived from the quote's recurring lines.
 * If every recurring line shares one cadence, bill the per-period sum in that
 * cadence (10 000/mo stays 10 000/mo). Mixed cadences normalise to monthly —
 * the only honest common denominator. One-time lines are NOT part of the
 * recurring billing (they belong on the first invoice). Null when nothing recurs.
 */
export function deriveContractBilling(lines: RecurringLineInput[]): ContractBillingSeed | null {
  const recurring = lines.filter((l) => l.recurrence === 'month' || l.recurrence === 'year');
  if (recurring.length === 0) return null;
  const cadences = new Set(recurring.map((l) => l.recurrence));
  if (cadences.size === 1) {
    const interval = recurring[0].recurrence as 'month' | 'year';
    const amount = recurring.reduce((sum, l) => sum + effectiveCents(l), 0);
    return { billing_amount_cents: amount, billing_interval: interval };
  }
  const monthly = recurring.reduce((sum, l) => sum + monthlyCents(l), 0);
  return { billing_amount_cents: monthly, billing_interval: 'month' };
}
