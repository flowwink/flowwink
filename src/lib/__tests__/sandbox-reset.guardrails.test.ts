import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PLATFORM_SKILLS } from '@/lib/platform-seeds';

/**
 * Guardrail: the sandbox reset can never fire on a customer instance, and
 * always preserves the layers a reset must not destroy.
 *
 * sandbox.flowwink.com's model (Magnus, 2026-07-22): testers get FULL admin;
 * the nightly rebuild is the safety mechanism. That makes reset_sandbox the
 * most dangerous skill in the fleet if its gates ever loosen — it is seeded
 * everywhere (artifact parity), so the gates ARE the product.
 */

const root = process.cwd();
// The LATEST definition of the wipe. A guardrail reading a superseded file
// would certify a body no instance runs — so this must move with the function.
const mig = readFileSync(join(root, 'supabase/migrations/20260813100000_a-wipe-must-not-destroy-what-only-a-migration-provides.sql'), 'utf8');
const ae = readFileSync(join(root, 'supabase/functions/agent-execute/index.ts'), 'utf8');

describe('sandbox reset safety', () => {
  it('the SQL wipe is triple-gated and atomic', () => {
    expect(mig).toContain("p_confirm IS DISTINCT FROM 'WIPE-SANDBOX'");
    // Gate = the visible Demo Mode toggle (legacy sandbox_mode honored).
    expect(mig).toMatch(/demo_mode/);
    expect(mig).toMatch(/auth\.role\(\) = 'service_role' OR has_role/);
    // Invariant check that rolls the whole transaction back on keep-table damage.
    expect(mig).toMatch(/rollback: a keep-table was emptied/);
  });

  it('the keep-list preserves every seeded layer, identity and credentials', () => {
    // Reference data whose only source is a migration MUST survive: migrations
    // do not re-run, so a wipe that takes them is permanent. Losing
    // payroll_country_profiles broke the hr seeder on the first rebuilt night;
    // the sweep that followed found seventeen more, including the role/nav
    // matrix from the post-squash empty-views incident and the VAT box map.
    for (const t of [
      'payroll_country_profiles',
      'role_module_access',
      'role_module_access_defaults',
      'account_tax_boxes',
      'journals',
      'currencies',
      'pipeline_stages',
      'uoms',
      'agent_skills',
      'agent_automations',
      'chart_of_accounts',
      'account_roles',
      'accounting_templates',
      'locale_packs',
      'site_settings',
      'user_roles',
      'profiles',
      'api_keys',
    ]) {
      expect(mig, `${t} missing from the wipe keep-list`).toMatch(new RegExp(`'${t}'`));
    }
  });

  it('the wipe is not executable by ordinary authenticated users', () => {
    expect(mig).toMatch(/REVOKE ALL ON FUNCTION public\.sandbox_reset_wipe/);
    expect(mig, 'wipe granted to authenticated').not.toMatch(/GRANT EXECUTE ON FUNCTION public\.sandbox_reset_wipe\(text\) TO authenticated/);
  });

  it('the handler refuses on non-sandbox instances BEFORE calling the wipe', () => {
    const start = ae.indexOf('async function executeResetSandbox');
    expect(start).toBeGreaterThan(0);
    const body = ae.slice(start, ae.indexOf('async function', start + 10));
    const refusal = body.indexOf('reset_sandbox refused');
    const rpc = body.indexOf("rpc('sandbox_reset_wipe'");
    expect(refusal).toBeGreaterThan(0);
    expect(rpc).toBeGreaterThan(refusal);
    // And the wipe call carries the confirm token, never a variable.
    expect(body).toContain("p_confirm: 'WIPE-SANDBOX'");
  });

  it('the skill seed is marked demo-only for the model that will see it fleet-wide', () => {
    const skill = PLATFORM_SKILLS.find((s) => s.name === 'reset_sandbox');
    expect(skill).toBeTruthy();
    expect(skill?.handler).toBe('internal:reset_sandbox');
    expect(skill?.description).toMatch(/^DEMO INSTANCE ONLY/);
  });

  it('demo-cycle runs the full rebuild through the skill rail, gated the same way', () => {
    // One toggle, one implementation: the nightly job must not grow its own
    // wipe path — it calls reset_sandbox via agent-execute so the gates and
    // the agent_activity evidence live in exactly one place.
    const dc = readFileSync(join(root, 'supabase/functions/demo-cycle/index.ts'), 'utf8');
    expect(dc).toMatch(/skill_name: "reset_sandbox"/);
    expect(dc).toMatch(/demo_mode/);
    expect(dc, 'the rebuild must not bypass the rail with its own wipe call')
      .not.toMatch(/rpc\("sandbox_reset_wipe"/);
  });
});
