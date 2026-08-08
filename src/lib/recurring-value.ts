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
