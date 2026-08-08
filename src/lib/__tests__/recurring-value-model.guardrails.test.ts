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
const quoteSheet = readFileSync(
  resolve(__dirname, '../../../src/components/admin/quotes/QuoteDetailSheet.tsx'), 'utf-8');
const contractDialog = readFileSync(
  resolve(__dirname, '../../../src/components/admin/contracts/NewContractDialog.tsx'), 'utf-8');
const subscriptionBirth = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808350000_portal-ticket-and-delivery.sql'), 'utf-8');

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

describe('step 4: the dimension travels quote → contract → subscription', () => {
  it('the quote hands the contract its recurring billing and term, and TCV as value', () => {
    // The prefill is the seam. Before this, value_cents was quote.total_cents —
    // ONE period's total posing as the agreement's worth.
    expect(quoteSheet).toMatch(/billing:\s*deriveContractBilling\(lineItems\)/);
    expect(quoteSheet).toMatch(/term_months:/);
    expect(quoteSheet).toMatch(/rollup\.tcvCents\s*:\s*quote\.total_cents/);
  });

  it('the dialog derives the end date from the term — visibly, in the form', () => {
    // create_subscription_from_contract computes commitment_months from
    // start/end; deriving the dates up front means the commitment the customer
    // signs is the one the service is born with.
    expect(contractDialog).toMatch(/prefill\?\.term_months/);
    expect(contractDialog).toMatch(/end\.setMonth\(end\.getMonth\(\) \+ prefill\.term_months\)/);
  });

  it('the dialog writes the billing terms onto the born agreement (both paths)', () => {
    // Template path: post-create UPDATE. Blank path: insert payload.
    expect(contractDialog).toMatch(/billing_amount_cents:\s*prefill\.billing\.billing_amount_cents/);
    expect(contractDialog).toMatch(/billing_interval:\s*prefill\.billing\.billing_interval/);
  });

  it('the born service inherits amount, interval and commitment from the contract', () => {
    // The step-4 verification: create_subscription_from_contract (already
    // shipped) reads exactly the fields the dialog now seeds.
    const birth = subscriptionBirth.slice(subscriptionBirth.indexOf('create_subscription_from_contract'));
    expect(birth).toMatch(/COALESCE\(c\.billing_amount_cents, c\.value_cents, 0\)/);
    expect(birth).toMatch(/NULLIF\(c\.billing_interval, ''\)/);
    expect(birth).toMatch(/commitment_months/);
    expect(birth).toMatch(/age\(c\.end_date, c\.start_date\)/);
  });
});

describe('step 3: the deal headlines a derived basis, configured as data', () => {
  const dealsPage = readFileSync(
    resolve(__dirname, '../../../src/pages/admin/DealsPage.tsx'), 'utf-8');
  const kanbanCard = readFileSync(
    resolve(__dirname, '../../../src/components/admin/DealKanbanCard.tsx'), 'utf-8');
  const settings = readFileSync(
    resolve(__dirname, '../../../src/hooks/useSiteSettings.tsx'), 'utf-8');

  it('the basis is a site setting (data), never a tenant code branch', () => {
    expect(settings).toMatch(/deal_value_basis:\s*'per_period'\s*\|\s*'arr'\s*\|\s*'tcv'/);
    expect(settings).toMatch(/useSiteSettings<SalesPipelineSettings>\('sales_pipeline'/);
  });

  it('both deal surfaces render through dealHeadline, not raw value_cents', () => {
    expect(kanbanCard).toMatch(/dealHeadline\(deal\.product, deal\.value_cents/);
    expect(dealsPage).toMatch(/dealHeadline\(deal\.product, deal\.value_cents/);
  });
});
