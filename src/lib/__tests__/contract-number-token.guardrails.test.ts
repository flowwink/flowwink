/**
 * The agreement names itself — and the validator agrees.
 *
 * `{{contract.number}}` (and its legacy alias `[AVTALSNR]`) render to the
 * freshly-minted agreement number: the renderer mints the number up front, drops
 * it into the body, and stores it on the row — proven live, a draft reads
 * "Avtalsnummer: AGR-2026-00017". The number IS the order number (avtal = order),
 * so a contract that can't print its own number is a contract that can't be
 * referred to.
 *
 * The renderer and the authoring guard are two views of ONE token set. They had
 * drifted: the renderer substituted {{contract.number}} while the guard's
 * allowlist never listed it, so a template that used the token was falsely
 * flagged as carrying an unrendered placeholder. This locks them aligned.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const read = (p: string) => readFileSync(join(process.cwd(), p), 'utf-8');
// The renderer's current definition (CREATE OR REPLACE, comments stripped).
const render = read('supabase/migrations/20260808250000_terms-slug-setting.sql').replace(/--[^\n]*/g, '');
// The guard's current definition — the migration that added contract.number.
const guard = read('supabase/migrations/20260808360000_contract-number-token-in-guard.sql');

describe('the renderer prints the agreement number', () => {
  it('mints the number before rendering the body', () => {
    const mintAt = render.indexOf("next_document_number('contract', 'AGR')");
    const renderAt = render.indexOf("'{{contract.number}}', v_number");
    expect(mintAt).toBeGreaterThan(-1);
    expect(renderAt).toBeGreaterThan(-1);
    expect(mintAt).toBeLessThan(renderAt); // known before it's substituted
  });

  it('substitutes the token and its legacy [AVTALSNR] alias', () => {
    expect(render).toContain("replace(v_body, '{{contract.number}}', v_number)");
    expect(render).toContain("replace(v_body, '[AVTALSNR]', v_number)");
  });

  it('stores the number on the row so the trigger never reassigns it', () => {
    // assign_contract_number only fills a NULL — passing v_number keeps the
    // number in the body identical to the number on the record.
    expect(render).toMatch(/contract_number[\s\S]*VALUES[\s\S]*v_number/);
  });
});

describe('the guard accepts what the renderer fills', () => {
  it('allowlists contract.number', () => {
    expect(guard).toContain("'contract.number'");
  });

  it('keeps the tokens already agreed, so this is additive not a reset', () => {
    for (const t of ['counterparty.name', 'supplier.name', 'supplier.signatory',
                     'counterparty.org_number', 'terms_url', 'site_url', 'quote.lines']) {
      expect(guard).toContain(`'${t}'`);
    }
  });
});
