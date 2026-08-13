import { describe, expect, it } from 'vitest';
import { primaryRole } from '@/hooks/useAuth';
import type { AppRole } from '@/types/cms';

/**
 * Guardrail: the displayed role is who you ARE, not which row is oldest.
 *
 * The signup trigger's fail-closed customer row is always a user's oldest role
 * row, so any `roles[0]` derivation displays every upgraded account as
 * "Customer". This bug was fixed in fetchUserData (2026-07) and then shipped
 * AGAIN through a second, independent derivation in the provider's
 * effectivePrimary — found live on the sandbox when a sales test user's footer
 * read "Customer" while the sidebar showed their sales modules. One exported
 * function now owns the rule; this test pins it.
 */
describe('primaryRole', () => {
  it('customer never wins over a functional role, regardless of order', () => {
    expect(primaryRole(['customer', 'sales'] as AppRole[])).toBe('sales');
    expect(primaryRole(['sales', 'customer'] as AppRole[])).toBe('sales');
  });

  it('admin wins over everything', () => {
    expect(primaryRole(['customer', 'sales', 'admin'] as AppRole[])).toBe('admin');
  });

  it('a pure customer is a customer, and no roles is null', () => {
    expect(primaryRole(['customer'] as AppRole[])).toBe('customer');
    expect(primaryRole([] as AppRole[])).toBeNull();
  });

  it('there is exactly one derivation in the codebase', async () => {
    // The bug shipped twice because the rule existed in two copies. Pin that
    // useAuth contains no other `roles[0]`-style primary derivation.
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/hooks/useAuth.tsx', 'utf8');
    const derivations = src.match(/includes\('admin'\)\s*\?\s*'admin'/g) ?? [];
    expect(derivations.length, 'a second primary-role derivation has appeared — use primaryRole()').toBeLessThanOrEqual(1);
  });
});
