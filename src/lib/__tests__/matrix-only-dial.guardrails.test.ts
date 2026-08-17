import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Rollsvepet #102: the matrix (role_module_access) is the ONLY dial.
 *
 * The sweep found two structural holes and a family of shadow matrices:
 * agent-execute 401'd every non-admin JWT out of the whole skill layer, and
 * three frontend surfaces carried hardcoded `roles: [...]` lists beside a
 * moduleId — lists the matrix can never reach, so a granted role still saw
 * nothing. These tests pin the repaired invariants so the class stays dead.
 */
const read = (p: string) => readFileSync(join(process.cwd(), p), 'utf-8');

describe('agent-execute authorizes per the skill’s owning module', () => {
  const src = read('supabase/functions/agent-execute/index.ts');

  it('builds the skill → module ownership map from the bundled artifact', () => {
    expect(src).toContain('SKILL_OWNER_MODULE');
    expect(src).toMatch(/for \(const mod of \(bundledModuleSkills/);
  });

  it('gates non-admin JWT callers with can_access_module, after the skill lookup', () => {
    expect(src).toMatch(/can_access_module/);
    // The old shape — 401 for every non-admin before the body is read — must
    // not come back: authentication may reject unknowns, but a resolved user
    // without admin proceeds to per-skill authorization.
    expect(src).toContain('if (!isServiceCaller && !gateUserId)');
    expect(src).toContain('if (!isServiceCaller && !gateIsAdmin)');
  });

  it('fails closed: platform-owned and unmapped skills stay admin-only', () => {
    expect(src).toMatch(/ownerModule !== 'platform'/);
  });

  it('the 403 names the module and the dial, so a denial self-corrects', () => {
    expect(src).toContain('Role Permissions');
  });
});

describe('no shadow role lists beside a moduleId (frontend)', () => {
  it('dashboard widget relevance reads the matrix, not a third role list', () => {
    const presets = read('src/lib/dashboard-presets.ts');
    expect(presets).toMatch(/canAccess: \(moduleId: string\) => boolean/);
    // ROLE_PRESETS (personalization defaults) are allowed — widget-level
    // `roles:` gates are not.
    const catalog = presets.split('ROLE_PRESETS')[0];
    expect(catalog).not.toMatch(/roles: \[/);
  });

  it('the ⌘K palette filters nav hits on the matrix, same as the sidebar', () => {
    const cmd = read('src/components/admin/AdminSearchCommand.tsx');
    expect(cmd).toMatch(/canAccess\(item\.moduleId\)/);
  });

  it('expense approval follows the expenses module, not the admin role', () => {
    const tab = read('src/components/admin/expenses/ExpenseReportsTab.tsx');
    expect(tab).toMatch(/canAccess\('expenses'\)/);
    expect(tab).not.toMatch(/\bisAdmin\b/);
  });
});

describe('nav honesty: one module id, one answer', () => {
  const nav = read('src/components/admin/adminNavigation.ts');

  it('Campaigns follows paidGrowth (the "developer" copy-paste bug stays dead)', () => {
    expect(nav).not.toMatch(/Campaigns[^\n]*moduleId: "developer"/);
    expect(nav).toMatch(/Campaigns[^\n]*moduleId: "paidGrowth"/);
  });

  it('only the documented platform tools keep a moduleId inside adminOnly groups', () => {
    // Templates + Developer are deliberately admin-only platform tooling.
    // Any OTHER moduleId-carrying item inside an adminOnly group repeats the
    // POS-Audit bug: the same module id answered differently per code path.
    const groups = nav.split(/\{\s*\n\s*(?:\/\/[^\n]*\n\s*)*label:/).slice(1);
    const offenders: string[] = [];
    for (const g of groups) {
      if (!/adminOnly:\s*true/.test(g)) continue;
      for (const m of g.matchAll(/name: "([^"]+)"[^\n]*moduleId: "([^"]+)"/g)) {
        if (!['Templates', 'Developer'].includes(m[1])) offenders.push(`${m[1]} (${m[2]})`);
      }
    }
    expect(offenders, `moduleId-bärande rader fångna i adminOnly-grupper: ${offenders.join(', ')}`).toEqual([]);
  });
});

describe('staff means non-customer', () => {
  it('isWriter never counts the customer role as staff', () => {
    const auth = read('src/hooks/useAuth.tsx');
    expect(auth).toMatch(/effectiveRoles\.some\(\(r\) => r !== 'customer'\)/);
    expect(auth).not.toContain('effectiveRoles.length > 0;');
  });
});

describe('every ai-task declares its owning module', () => {
  it('TaskSpec.module is required and every task sets it', () => {
    const tasks = read('supabase/functions/ai-task/tasks.ts');
    expect(tasks).toMatch(/^\s+module: string;/m);
    const names = [...tasks.matchAll(/^\s+name: "([a-z_]+)",$/gm)].map((m) => m[1]);
    const withModule = [...tasks.matchAll(/^\s+name: "([a-z_]+)",\n\s+module: "/gm)].map((m) => m[1]);
    // Every task registered by name must be immediately followed by module.
    const taskNames = names.filter((n) => !n.startsWith('submit_') && !n.startsWith('extract_'));
    for (const n of taskNames) {
      expect(withModule, `task "${n}" saknar module-fält`).toContain(n);
    }
  });
});
