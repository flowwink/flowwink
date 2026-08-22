/**
 * Guardrail: the client's module defaults must be able to REACH the server.
 *
 * The bug class, not the instance. Two readers of `site_settings.modules`
 * disagree about what an ABSENT row means, and each is internally consistent:
 *
 *   • src/hooks/useModules.tsx — `{...defaultModulesSettings, ...stored}`.
 *     An absent row merges to the code defaults, so /admin renders a configured
 *     product (7 modules enabled, nav populated). It never persists the merge.
 *   • supabase/functions/_shared/modules.ts — `value?.[name]?.enabled === true`.
 *     An absent row is `{}`, so every module reads OFF. No default merge, by
 *     design: the server must not invent an operator's configuration.
 *
 * Neither is wrong alone. Together they are a split brain, and the symptoms are
 * all silent: ~20 edge functions no-op (instance-health, event-dispatcher,
 * automation-dispatcher, newsletter-send, the MCP exposure in agent-execute,
 * flowpilot-heartbeat), and `sync_skills_from_code` — module-gated server-side —
 * syncs only the `platform` pseudo-module, landing a fresh install on 14 skills
 * instead of ~150 while reporting success.
 *
 * Verified on the local fresh replay (485 migrations, 2026-08-22):
 * `site_settings` held `cookie_consent_v2` and `visitor_intelligence_rules`.
 * No `modules` row. The admin UI showed a healthy product anyway.
 *
 * The invariant these tests defend: SOMETHING must persist the code defaults
 * into the row, at birth and afterwards, and NOTHING may write the row empty.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');

const SEED_FN = 'ensure_modules_settings';

function migrationsContaining(needle: string): string[] {
  return readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .filter((f) => readFileSync(join(MIGRATIONS, f), 'utf8').includes(needle));
}

describe('the modules row is seeded at birth', () => {
  it('a migration defines the re-assertable seed function', () => {
    const files = migrationsContaining(`FUNCTION public.${SEED_FN}`);
    expect(
      files.length,
      `No migration defines public.${SEED_FN}(). Without it a fresh install has no ` +
        'site_settings.modules row at all, and every server-side module gate reads OFF.',
    ).toBeGreaterThan(0);

    // Re-assertable, not a one-shot INSERT. A squash or a partial replay must be
    // able to re-run it (the role_module_access_defaults lesson).
    const sql = files.map((f) => readFileSync(join(MIGRATIONS, f), 'utf8')).join('\n');
    expect(sql).toMatch(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${SEED_FN}`));
  });

  it('a migration actually CALLS the seed function — defining it is not seeding', () => {
    const called = migrationsContaining(`${SEED_FN}(`).some((f) => {
      const sql = readFileSync(join(MIGRATIONS, f), 'utf8');
      // A call site outside the CREATE FUNCTION body: SELECT/PERFORM/assignment.
      return /(?:SELECT|PERFORM|:=)\s*(?:public\.)?ensure_modules_settings\s*\(/i.test(
        sql.replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$fn\$[\s\S]*?\$fn\$;/g, ''),
      );
    });
    expect(
      called,
      `public.${SEED_FN}() exists but no migration invokes it. A function nobody calls ` +
        'leaves the fresh instance exactly as broken as before.',
    ).toBe(true);
  });

  it('never overwrites an existing row — the operator\'s choice always wins', () => {
    const sql = migrationsContaining(`FUNCTION public.${SEED_FN}`)
      .map((f) => readFileSync(join(MIGRATIONS, f), 'utf8'))
      .join('\n');

    // The fill-in path must be conditional on the key being ABSENT.
    expect(
      /IF NOT \(v_existing \? k\)/.test(sql),
      `${SEED_FN} must only add module keys that are MISSING. An unconditional ` +
        'merge would silently re-enable modules an operator turned off.',
    ).toBe(true);
  });
});

describe('the code defaults keep reaching the row after install', () => {
  it('a runtime caller passes the live defaultModulesSettings into the seed RPC', () => {
    // A migration is frozen by the ledger the moment it runs, so its snapshot can
    // only ever be the head start. Without a runtime caller, every module added
    // to the code after install is invisible to the server forever.
    const bootstrap = read('src/lib/module-bootstrap.ts');
    expect(bootstrap).toContain(SEED_FN);
    expect(bootstrap).toMatch(/export function ensureModulesRow/);

    const hook = read('src/hooks/useFlowPilotBootstrap.ts');
    expect(
      /ensureModulesRow\(\s*defaultModulesSettings\s*\)/.test(hook),
      'The admin shell must call ensureModulesRow(defaultModulesSettings) so the LIVE ' +
        'code defaults — not a frozen migration snapshot — are the source of truth.',
    ).toBe(true);
  });

  it('reads the row BACK and reports what is still missing', () => {
    const bootstrap = read('src/lib/module-bootstrap.ts');
    const fn = bootstrap.slice(bootstrap.indexOf('export function ensureModulesRow'));
    expect(
      /from\('site_settings'\)[\s\S]{0,200}eq\('key', 'modules'\)/.test(fn),
      'ensureModulesRow must re-read the row after writing. The RPC\'s own report is ' +
        'the writer marking its own homework — the exact shape of the silent no-op alias bug.',
    ).toBe(true);
    expect(fn).toMatch(/logger\.error/);
  });

  it('the seed runs before the skill sync, which is module-gated server-side', () => {
    const hook = read('src/hooks/useFlowPilotBootstrap.ts')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/\/\/[^\n]*/g, '');
    const seedAt = hook.indexOf('await ensureModulesRow(defaultModulesSettings)');
    const syncAt = hook.indexOf('await ensureSkillRegistry()');
    expect(seedAt).toBeGreaterThan(-1);
    expect(syncAt).toBeGreaterThan(-1);
    expect(
      seedAt < syncAt,
      'sync_skills_from_code reads site_settings.modules. Run it before the row exists ' +
        'and it syncs the `platform` pseudo-module alone — 14 skills, reported as success.',
    ).toBe(true);
  });
});

describe('nothing writes the modules row empty', () => {
  it('no source file stores `{}` under the modules key', () => {
    // ResetSiteDialog did exactly this, manufacturing the split brain on a
    // MATURE instance — where the platform self-heal early-returns (skills are
    // present) and would never have repaired it.
    const offenders: string[] = [];
    const walk = (dir: string) => {
      for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
        const rel = `${dir}/${entry.name}`;
        if (entry.isDirectory()) {
          if (entry.name === '__tests__' || entry.name === 'node_modules') continue;
          walk(rel);
        } else if (/\.tsx?$/.test(entry.name)) {
          // Comments describe the bug; only CODE can commit it.
          const src = readFileSync(join(ROOT, rel), 'utf8')
            .replace(/\/\*[\s\S]*?\*\//g, '')
            .replace(/\/\/[^\n]*/g, '');
          if (/key:\s*'modules',\s*value:\s*\{\s*\}/.test(src)) offenders.push(rel);
          if (/\{\s*key:\s*'modules'\s*\}[\s\S]{0,40}value:\s*\{\s*\}/.test(src)) offenders.push(rel);
        }
      }
    };
    walk('src');

    expect(
      offenders,
      'Writing an empty modules row is not "reset to defaults" — it is the split brain. ' +
        'Write the defaults derived from defaultModulesSettings instead.',
    ).toEqual([]);
  });

  it('the site reset writes the code defaults', () => {
    const reset = read('src/components/admin/ResetSiteDialog.tsx');
    expect(reset).toMatch(/defaultModulesSettings/);
    expect(reset).toMatch(/key:\s*'modules',\s*value:\s*modulesResetValue\(\)/);
  });
});
