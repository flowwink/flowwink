import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * `composio-proxy` accepts the ANON key as a caller, because pg_cron has no
 * service key to offer. That key ships inside the frontend bundle, so it is
 * public by construction — anything it unlocks, the internet unlocks.
 *
 * The endpoint it unlocks polls the company mailbox. Withholding message
 * content from the response is necessary but not sufficient: if the caller
 * chooses the Gmail `query`, the surviving count becomes a search oracle. Ask
 * "from:swedbank", read the number, ask again. Each call also spends a real
 * Composio request, and nothing rate-limits it.
 *
 * These pin the three properties that keep a public key from being a useful
 * one: it reaches a single action, it chooses none of that action's inputs, and
 * it reads back no message data.
 */

const proxy = readFileSync(
  resolve(__dirname, '../../../supabase/functions/composio-proxy/index.ts'),
  'utf-8',
);

/** The gmail_reconcile branch, isolated from the rest of the dispatch. */
function reconcileBranch(): string {
  const start = proxy.indexOf("if (action === 'gmail_reconcile')");
  expect(start, 'gmail_reconcile branch not found — this guard is reading the wrong file').toBeGreaterThan(-1);
  const next = proxy.indexOf("if (action === '", start + 10);
  return proxy.slice(start, next > -1 ? next : start + 4000);
}

describe('the anon-key caller is identified as untrusted', () => {
  it('is recognised by comparing against the anon key, not assumed', () => {
    expect(proxy).toMatch(/const isCronCaller\s*=[\s\S]{0,120}token === anonKey/);
  });

  it('reaches exactly one action', () => {
    // Anything else must be rejected before the dispatch runs.
    expect(proxy).toMatch(/if \(isCronCaller && action !== 'gmail_reconcile'\)/);
  });
});

describe('the anon-key caller chooses none of the poll inputs', () => {
  const branch = reconcileBranch();

  it('derives a trust flag rather than reading params directly', () => {
    expect(branch).toMatch(/const trusted = !isCronCaller/);
  });

  it('does not let it pick the Gmail query — the search-oracle hole', () => {
    const queryLine = branch.split('\n').find((l) => /const query\s*=/.test(l)) ?? '';
    expect(queryLine, 'query must be gated on `trusted`').toMatch(/trusted/);
    expect(queryLine).toMatch(/in:inbox/); // a fixed server-side sweep remains the fallback
  });

  it('does not let it pick the page size', () => {
    const line = branch.split('\n').find((l) => /const maxResults\s*=/.test(l)) ?? '';
    expect(line, 'max_results must be gated on `trusted`').toMatch(/trusted/);
  });

  it('does not let it target another connected account', () => {
    const line = branch.split('\n').find((l) => /const accountId\s*=/.test(l)) ?? '';
    expect(line, 'account_id must be gated on `trusted`').toMatch(/trusted/);
  });
});

describe('the anon-key caller reads back no message data', () => {
  it('gets counts only, never the per-message results', () => {
    const branch = reconcileBranch();
    // The shape is chosen by isCronCaller: counts for it, details for service-role.
    expect(branch).toMatch(/isCronCaller\s*\?\s*\{ fetched[^}]*ingested \}/);
    expect(branch).toMatch(/:\s*\{ fetched[^}]*results \}/);
  });
});
