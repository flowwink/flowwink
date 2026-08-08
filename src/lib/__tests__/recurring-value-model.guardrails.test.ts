import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The recurring-value model — a price keeps its dimension from product to quote.
 * The load-bearing invariants: the additions are product-driven, additive and
 * nullable (so the one-time product-sales flow is untouched), and the rollups
 * are derived, never typed. See docs/architecture/recurring-value-model.md.
 */

const productMig = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808370000_product-cadence.sql'), 'utf-8');
const quoteMig = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808380000_quote-line-recurrence.sql'), 'utf-8');

describe('the cadence lives on the product, additive and nullable', () => {
  it('adds billing_interval + default_term_months to products', () => {
    expect(productMig).toMatch(/ADD COLUMN IF NOT EXISTS billing_interval text/);
    expect(productMig).toMatch(/ADD COLUMN IF NOT EXISTS default_term_months integer/);
  });

  it('constrains the interval to month|year but allows NULL', () => {
    expect(productMig).toMatch(/billing_interval IS NULL OR billing_interval IN \('month', 'year'\)/);
  });

  it('backfills recurring products to monthly and leaves one_time untouched', () => {
    // The one-time flow must be unaffected: no UPDATE targets type='one_time'.
    expect(productMig).toMatch(/SET billing_interval = 'month'\s*WHERE type = 'recurring'/);
    expect(productMig).not.toMatch(/WHERE type = 'one_time'/);
  });
});

describe('the quote carries a default binding term', () => {
  it('adds quotes.default_term_months, nullable and positive', () => {
    expect(quoteMig).toMatch(/ALTER TABLE public\.quotes\s*ADD COLUMN IF NOT EXISTS default_term_months integer/);
    expect(quoteMig).toMatch(/default_term_months IS NULL OR default_term_months > 0/);
  });

  it('does NOT touch the dead quote_items table', () => {
    // quote_items has 0 rows and is superseded by the JSONB quotes.line_items;
    // per-line recurrence rides in the InvoiceLineItem shape, not a table column.
    // (The comment legitimately names quote_items to explain why — strip it.)
    const code = quoteMig.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
    expect(code).not.toMatch(/quote_items/);
  });
});
