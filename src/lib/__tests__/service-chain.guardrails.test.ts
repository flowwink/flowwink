import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The service chain: signed contract → subscription (the service) → portal →
 * ticket. The load-bearing rule is ONE INVOICER: a service born from a
 * contract is billed by the contract, never also by the subscription cron.
 */

const migration = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808310000_service-chain-contract-to-subscription.sql'),
  'utf-8',
);
const subCron = readFileSync(
  resolve(__dirname, '../../../supabase/functions/subscription-billing-cron/index.ts'),
  'utf-8',
);
const contractSign = readFileSync(
  resolve(__dirname, '../../../supabase/functions/contract-sign/index.ts'),
  'utf-8',
);

describe('the one-invoicer rule holds structurally', () => {
  it("subscription-billing-cron bills provider='manual' only", () => {
    // A contract-born row is provider='contract', so this filter is what keeps
    // the subscription cron from double-billing it. If this ever widens, the
    // rule erodes silently — hence the guard.
    expect(subCron).toMatch(/\.eq\(\s*["']provider["']\s*,\s*["']manual["']\s*\)/);
  });

  it("the birth function stamps provider='contract'", () => {
    // The marker that excludes the row from the subscription cron. The
    // contract keeps billing via contract-billing-cron (billing_enabled).
    // Strip comments — the SQL comment legitimately mentions 'manual' to
    // explain the rule; only the INSERT must not use it.
    const fn = migration
      .slice(migration.indexOf('create_subscription_from_contract'))
      .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
    expect(fn).toMatch(/'contract'/);
    expect(fn).not.toMatch(/'manual'/); // never born as a self-billing row
  });
});

describe('a contract mints at most one service', () => {
  it('a unique index enforces one subscription per contract', () => {
    expect(migration).toMatch(/CREATE UNIQUE INDEX[\s\S]*subscriptions\(contract_id\)/i);
  });

  it('the birth function returns the existing service instead of a second', () => {
    const fn = migration.slice(migration.indexOf('create_subscription_from_contract'));
    expect(fn).toMatch(/SELECT id INTO v_sub_id[\s\S]*WHERE contract_id = p_contract_id/);
    expect(fn).toMatch(/IF v_sub_id IS NOT NULL THEN[\s\S]*RETURN v_sub_id/);
  });
});

describe('signing creates the service without risking the signature', () => {
  it('contract-sign calls the birth function on accept', () => {
    expect(contractSign).toMatch(/create_subscription_from_contract/);
  });

  it('a failed service creation never throws — the signature is what matters', () => {
    const block = contractSign.slice(
      contractSign.indexOf('create_subscription_from_contract') - 200,
      contractSign.indexOf('create_subscription_from_contract') + 300,
    );
    // logged, not thrown
    expect(block).toMatch(/console\.error/);
    expect(block).not.toMatch(/throw subErr/);
  });
});

describe('commitment flows from the agreement, not re-entered', () => {
  it('term derives from the contract dates / billing interval', () => {
    const fn = migration.slice(migration.indexOf('create_subscription_from_contract'));
    expect(fn).toMatch(/commitment_months/);
    expect(fn).toMatch(/c\.start_date/);
    expect(fn).toMatch(/c\.billing_interval/);
  });
});

describe('the ticket can point at the service', () => {
  it('tickets gains subscription_id', () => {
    expect(migration).toMatch(/ALTER TABLE public\.tickets[\s\S]*subscription_id uuid/);
  });
});

describe('portal RLS reads the JWT, never auth.users', () => {
  // The first version selected from auth.users, which `authenticated` cannot
  // read — "permission denied for table users" failed the WHOLE policy, so
  // neither customer nor admin saw any subscription (admin page blank). A
  // policy that reads a privileged table is a policy that reads nothing.
  const fix = readFileSync(
    resolve(__dirname, '../../../supabase/migrations/20260808320000_fix-subscription-portal-rls.sql'),
    'utf-8',
  );

  it('takes the caller email from the JWT, not a table', () => {
    expect(fix).toMatch(/auth\.jwt\(\)\s*->>\s*'email'/);
    const code = fix.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
    expect(code).not.toMatch(/FROM auth\.users/);
  });

  it('still lets staff see all', () => {
    expect(fix).toMatch(/is_staff\(auth\.uid\(\)\)/);
  });
});
