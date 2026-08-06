import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * AGR-2026-00005 rendered "[KUNDENS ORGNR]" while Liteit AB sat in companies
 * with org_number 556616-1658. The renderer's lookup was fine — the CHAIN was
 * severed: nothing filled quotes.company_id, so the contract inherited
 * nothing, and the exact name match ('liteit' vs 'Liteit AB') correctly
 * refused to guess. Identity must travel as an ID, with the name match as
 * last resort — never the only path into a legal document.
 */

const sql = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808230000_company-identity-travels.sql'),
  'utf-8',
);
const code = sql
  .split('\n')
  .filter((l) => !l.trim().startsWith('--'))
  .join('\n');

describe('identity travels as an ID', () => {
  it('quotes inherit company from deal → lead, as a trigger', () => {
    // A trigger, not dialog code: a quote is born three ways (UI, skill, RPC)
    // and a rule living in one of three places is the recurring bug class.
    expect(code).toMatch(/CREATE TRIGGER quotes_inherit_company/);
    expect(code).toMatch(/JOIN public\.leads l ON l\.id = d\.lead_id/);
  });

  it('contracts inherit company from their quote, as a trigger', () => {
    expect(code).toMatch(/CREATE TRIGGER contracts_inherit_company/);
  });

  it('backfills quotes before contracts — dependency order', () => {
    const quotesBackfill = code.indexOf('UPDATE public.quotes q');
    const contractsBackfill = code.indexOf('UPDATE public.contracts c');
    expect(quotesBackfill).toBeGreaterThan(-1);
    expect(contractsBackfill).toBeGreaterThan(quotesBackfill);
  });

  it('the renderer resolves via the quote BEFORE the name match', () => {
    // The trigger fires on INSERT — too late for tokens in the body text —
    // so the render function must resolve the company itself.
    const viaQuote = code.indexOf('COALESCE(q.company_id, l.company_id)');
    const nameMatch = code.indexOf('lower(name) = lower(trim(p_counterparty_name))');
    expect(viaQuote).toBeGreaterThan(-1);
    expect(nameMatch).toBeGreaterThan(viaQuote);
  });

  it('keeps the name match exact — no fuzzy matching into legal documents', () => {
    expect(code).not.toMatch(/similarity|levenshtein|% ?ILIKE ?%|ILIKE '%'/);
  });
});

describe('NULL cannot poison the body', () => {
  // replace() with one NULL argument nulls the ENTIRE body. The UI dialog
  // always sends value_cents so this never fired from there — an agent
  // calling the RPC bare, against a template with no default value, got a
  // NULL body inside a success envelope. The envelope lie, in SQL.
  it('value renders as a visible bracket when unknown', () => {
    expect(code).toMatch(/COALESCE\(to_char\(v_value[\s\S]{0,60}'\[BELOPP\]'\)/);
  });

  it('currency renders as a visible bracket when unknown', () => {
    expect(code).toMatch(/COALESCE\(v_currency, '\[VALUTA\]'\)/);
  });

  it('counterparty name is guarded', () => {
    expect(code).toMatch(/COALESCE\(p_counterparty_name, ''\)/);
  });
});

describe('the human surface shows what documents will say', () => {
  const page = readFileSync(
    resolve(__dirname, '../../pages/admin/CompanyDetailPage.tsx'),
    'utf-8',
  );

  it('org number is visible, editable, and its ABSENCE is visible too', () => {
    // The whole incident started with "varför finns inte companies org nr i
    // UI?" — the field lived in the schema and the agent surface only.
    expect(page).toMatch(/company\.org_number/);
    expect(page).toMatch(/editForm\.org_number/);
    expect(page).toMatch(/missing/); // absent org number renders a visible flag
  });

  it('vat number is visible and editable', () => {
    expect(page).toMatch(/company\.vat_number/);
    expect(page).toMatch(/editForm\.vat_number/);
  });
});
