import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  buildBundle, parseBundle, planImport, unknownTokens, toTransferable,
  KNOWN_TOKENS, BUNDLE_FORMAT,
  type TransferableTemplate,
} from '../contract-template-transfer';

const tpl = (over: Partial<TransferableTemplate> = {}): TransferableTemplate => ({
  name: 'Avtal — Test',
  description: null,
  contract_type: 'service',
  language: 'sv',
  body_markdown: '# Avtal\n\n{{counterparty.name}}',
  default_currency: 'SEK',
  default_renewal_type: 'none',
  default_renewal_notice_days: 30,
  default_value_cents: null,
  is_public: false,
  is_active: true,
  ...over,
});

describe('the token list cannot drift from the renderer', () => {
  // KNOWN_TOKENS gates import warnings; the DB allowlist gates authoring; the
  // renderer fills tokens. All three must agree — this reads the latest
  // migration's allowlist and compares set-for-set.
  const sql = readFileSync(
    resolve(__dirname, '../../../supabase/migrations/20260808240000_quote-lines-into-contract.sql'),
    'utf-8',
  );
  const allowlistBlock = sql.slice(
    sql.indexOf('_contract_template_unrendered_tokens'),
    sql.indexOf('$$;', sql.indexOf('_contract_template_unrendered_tokens')),
  );
  const migrationTokens = [...allowlistBlock.matchAll(/'([\w.]+)'/g)]
    .map((m) => m[1])
    .filter((t) => t.includes('.') || /^[a-z_]+$/.test(t))
    .filter((t) => !['g', 'jsonb'].includes(t));

  it('every migration token is known to the transfer lib', () => {
    for (const t of migrationTokens) {
      expect(KNOWN_TOKENS as readonly string[]).toContain(t);
    }
  });

  it('every transfer-lib token exists in the migration allowlist', () => {
    for (const t of KNOWN_TOKENS) {
      expect(allowlistBlock).toContain(`'${t}'`);
    }
  });
});

describe('bundle round-trip', () => {
  it('export → parse yields the same templates', () => {
    const bundle = buildBundle([tpl(), tpl({ name: 'Annan mall' })]);
    const parsed = parseBundle(JSON.stringify(bundle));
    expect(parsed.templates).toHaveLength(2);
    expect(parsed.templates[0].name).toBe('Avtal — Test');
    expect(parsed.format).toBe(BUNDLE_FORMAT);
  });

  it('toTransferable strips identity — no ids or timestamps travel', () => {
    const out = toTransferable({
      id: 'abc', created_at: 'x', updated_at: 'y', is_default: true,
      name: 'N', body_markdown: 'B', contract_type: 'service',
    });
    expect('id' in out).toBe(false);
    expect('updated_at' in out).toBe(false);
    expect('is_default' in out).toBe(false);
  });

  it('rejects junk with human messages', () => {
    expect(() => parseBundle('not json')).toThrow(/JSON/);
    expect(() => parseBundle('{"format":"other"}')).toThrow(/Not a contract template bundle/);
    expect(() => parseBundle(JSON.stringify({ format: BUNDLE_FORMAT, version: 99, templates: [tpl()] })))
      .toThrow(/newer/);
    expect(() => parseBundle(JSON.stringify({ format: BUNDLE_FORMAT, version: 1, templates: [] })))
      .toThrow(/no templates/);
    expect(() => parseBundle(JSON.stringify(buildBundle([tpl({ body_markdown: ' ' })]))))
      .toThrow(/empty body/);
  });
});

describe('import plan', () => {
  it('collisions are skipped, never overwritten', () => {
    // An existing template may be a version-frozen reference from signed
    // agreements — an import must not be able to rewrite it.
    const plan = planImport(buildBundle([tpl(), tpl({ name: 'Ny mall' })]), ['avtal — test']);
    expect(plan.find((p) => p.template.name === 'Avtal — Test')?.status).toBe('exists');
    expect(plan.find((p) => p.template.name === 'Ny mall')?.status).toBe('new');
  });

  it('flags tokens the renderer will not fill', () => {
    expect(unknownTokens('{{counterparty.name}} {{quote.lines}}')).toEqual([]);
    expect(unknownTokens('{{made.up}} och {{quote.lines}}')).toEqual(['made.up']);
  });
});
