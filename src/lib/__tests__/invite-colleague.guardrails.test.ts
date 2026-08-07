import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { FUNCTIONAL_ROLES } from '@/types/cms';

/**
 * Colleagues are invited by email with a functional role from the first
 * sign-in — the gap between create-user (right role, you set the password)
 * and invite-employee (real email, wrong role). The invitable list lives in
 * two places (the edge function's INVITABLE_ROLES and the dialog's INVITABLE)
 * and MUST equal admin + FUNCTIONAL_ROLES, or an admin picks a role the
 * backend then rejects — or worse, grants a role no page gates on.
 */

const fn = readFileSync(
  resolve(__dirname, '../../../supabase/functions/invite-colleague/index.ts'),
  'utf-8',
);
const dialog = readFileSync(
  resolve(__dirname, '../../components/admin/InviteColleagueDialog.tsx'),
  'utf-8',
);

describe('the invitable roles match the source of truth', () => {
  it('the edge function lists exactly admin + FUNCTIONAL_ROLES', () => {
    const block = fn.slice(fn.indexOf('INVITABLE_ROLES ='), fn.indexOf('];', fn.indexOf('INVITABLE_ROLES =')));
    for (const r of ['admin', ...FUNCTIONAL_ROLES]) {
      expect(block).toContain(`"${r}"`);
    }
    // No customer, no legacy writer/approver in the invite path.
    expect(block).not.toContain('"customer"');
    expect(block).not.toContain('"writer"');
    expect(block).not.toContain('"approver"');
  });

  it('the dialog builds its list from FUNCTIONAL_ROLES, not a hardcoded copy', () => {
    // Using the constant means the dialog cannot drift when a role is added.
    expect(dialog).toMatch(/\[\s*'admin'\s*,\s*\.\.\.FUNCTIONAL_ROLES\s*\]/);
  });
});

describe('the backend gates and reconciles correctly', () => {
  it('requires admin', () => {
    expect(fn).toMatch(/_role:\s*"admin"/);
    expect(fn).toContain('Admin role required');
  });

  it('sends a real email invite, not an admin-set password', () => {
    // The whole point vs create-user: Supabase Auth emails the invite and the
    // colleague sets their own password. So it invites, and never calls
    // createUser with a password field.
    expect(fn).toContain('inviteUserByEmail');
    const code = fn.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
    expect(code).not.toMatch(/createUser\(/);
    expect(code).not.toMatch(/password:/);
  });

  it('removes the trigger-seeded customer role on a fresh invite', () => {
    // Otherwise the colleague holds customer AND their function, and the
    // panel would show "Customer" (oldest row) — the bug we just fixed.
    const block = fn.slice(fn.indexOf('Reconcile roles'), fn.indexOf('audit_logs'));
    expect(block).toMatch(/delete\(\)[\s\S]*eq\("role", "customer"\)/);
  });

  it('does not strip roles when granting to an existing account', () => {
    // An admin adding a role to a colleague must not silently remove theirs.
    expect(fn).toMatch(/status === "invited"/);
  });
});
