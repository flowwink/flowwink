import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Spärr: a country's chart of accounts may never reach an instance through the
 * MIGRATION CHAIN.
 *
 * THE INCIDENT (2026-08-22). Every FlowWink install in the world was born with
 * 26 Swedish BAS accounts. Four migrations put them there, each for a local and
 * defensible reason — repair rows for posted journal lines, a payroll benefit
 * account, the reverse-charge VAT accounts, the SKV value-box purchase accounts
 * — and not one of them asked whether this instance had chosen Sweden.
 *
 * The invariant they defeated is stated in src/hooks/useTenantLocalePack.ts and
 * enforced by account_for(): empty-until-chosen. With no locale activated the
 * chart must be EMPTY and bookkeeping must refuse loudly, because a refusal
 * tells the operator to pick a standard. 26 rows made the chart look partly
 * configured instead, and the sanctioned way to load a real standard —
 * import_accounting_standard, with provenance and a sha256 gate — refused on a
 * virgin install with:
 *
 *     "locale se-bas2024 already has 26 accounts. Pass replace=true"
 *
 * Land är ett val, inte en default. Locale packs load at RUNTIME once the
 * operator picks a market (topUpLocalePackSeeds / import_accounting_standard,
 * 1262 accounts that never touch a migration). The chain's job is schema and
 * platform config — never one country's reference data.
 *
 * This file fails the next one that tries.
 */

const MIGRATIONS = join(__dirname, '../../../supabase/migrations');

/** The forward-dated cleanup that removes chain-planted rows on live instances. */
const CLEANUP = '20260822234500_e3f4a5b6-a-country-is-a-choice-not-a-default.sql';

/**
 * Byte ranges that are FUNCTION BODIES, not seed statements.
 *
 * import_accounting_standard contains `INSERT INTO chart_of_accounts` and
 * always will — that is the runtime loader this whole rule points people at.
 * It writes p_locale, never a literal, so a naive text scan would flag the
 * cure as the disease.
 */
function functionBodyRanges(sql: string): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
  for (const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION/gi)) {
    const tag = /AS\s+(\$[A-Za-z_]\w*\$|\$\$)/i.exec(sql.slice(m.index!, m.index! + 4000));
    if (!tag) continue;
    const open = m.index! + tag.index! + tag[0].length;
    const close = sql.indexOf(tag[1], open);
    ranges.push([m.index!, close === -1 ? sql.length : close + tag[1].length]);
  }
  return ranges;
}

interface Seed {
  file: string;
  codes: string[];
  locales: string[];
  guarded: boolean;
}

/** Every chart_of_accounts seed statement in the chain, outside function bodies. */
function chartSeeds(): Seed[] {
  const seeds: Seed[] = [];
  for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = readFileSync(join(MIGRATIONS, file), 'utf8');
    const bodies = functionBodyRanges(sql);

    for (const m of sql.matchAll(/INSERT\s+INTO\s+(?:public\.)?chart_of_accounts/gi)) {
      const at = m.index!;
      if (bodies.some(([a, b]) => at >= a && at < b)) continue;

      const rest = sql.slice(at);
      const end = /\)\s*;\s*\n/.exec(rest);
      const stmt = rest.slice(0, end ? end.index + end[0].length : 8000);

      // A locale literal is what makes a statement COUNTRY data. The runtime
      // loader parameterises it; a seed spells it out.
      const locales = [...new Set([...stmt.matchAll(/'([a-z]{2,3}-[a-z0-9]{3,})'/g)].map((x) => x[1]))];
      if (locales.length === 0) continue;

      seeds.push({
        file,
        locales,
        codes: [...new Set([...stmt.matchAll(/'(\d{4})'/g)].map((x) => x[1]))],
        // The guard reads site_settings.accounting_locale: seed only where the
        // operator has actually chosen this market (or the books already name
        // the code, which is a repair, not an opinion about the country).
        guarded: /accounting_locale/.test(stmt),
      });
    }
  }
  return seeds;
}

describe("a country is a choice, not a default", () => {
  const seeds = chartSeeds();

  it('no migration plants a country chart on an instance that never chose it', () => {
    const naked = seeds.filter((s) => !s.guarded);
    expect(
      naked.map((s) => `${s.file} → ${s.locales.join('/')}: ${s.codes.join(', ')}`),
      'These migrations seed a specific country\'s accounts unconditionally. A\n' +
        'chart belongs to the locale pack, loaded at runtime once an operator picks\n' +
        'a market (topUpLocalePackSeeds / import_accounting_standard) — never to the\n' +
        'migration chain, which runs identically in Stockholm and in Stuttgart.\n' +
        'If the rows really are a repair for books that already name the account,\n' +
        'gate the statement on site_settings.accounting_locale the way\n' +
        `${CLEANUP} describes.`,
    ).toEqual([]);
  });

  it('every code the chain can plant is covered by the cleanup migration', () => {
    // The cleanup only touches codes it lists, so an operator-created account is
    // never at risk. The flip side is that a NEW guarded seed would go
    // unnoticed on instances that already carry it. Keep the two in step.
    const cleanup = readFileSync(join(MIGRATIONS, CLEANUP), 'utf8');
    const covered = new Set([...cleanup.matchAll(/'(\d{4})'/g)].map((m) => m[1]));

    const uncovered = seeds
      .flatMap((s) => s.codes.map((c) => ({ file: s.file, code: c })))
      .filter((x) => !covered.has(x.code));

    expect(
      uncovered.map((x) => `${x.code} (${x.file})`),
      `${CLEANUP} removes chain-planted accounts from instances that never chose\n` +
        'a market — but only the codes it names. These are planted and not listed,\n' +
        'so they would survive on every existing install.',
    ).toEqual([]);
  });

  it('the cleanup never touches an instance that HAS chosen its market', () => {
    const cleanup = readFileSync(join(MIGRATIONS, CLEANUP), 'utf8');
    // An activated locale returns early — a Swedish instance keeps its chart.
    expect(cleanup).toMatch(/accounting_locale/);
    expect(cleanup).toMatch(/RETURN;/);
    // …and nothing that carries bookkeeping is removed, whatever the locale.
    expect(cleanup).toMatch(/NOT \(c\.account_code = ANY \(v_used\)\)/);
  });

  it('bookkeeping still refuses loudly on an unchosen instance', () => {
    // The refusal is the whole point of an empty chart. If account_for ever
    // falls back to a locale again, the seeds stop mattering and so does this
    // file.
    const f = readdirSync(MIGRATIONS).find((x) => x.includes('account-for-requires-activation'));
    expect(f, 'the empty-until-chosen migration is gone').toBeTruthy();
    const sql = readFileSync(join(MIGRATIONS, f!), 'utf8');
    expect(sql).toMatch(/IF _locale IS NULL THEN\s+RAISE EXCEPTION/);
    expect(sql).not.toMatch(/COALESCE\([^)]*'se-bas2024'/);

    const hook = readFileSync(join(__dirname, '../../hooks/useTenantLocalePack.ts'), 'utf8');
    // Seeding keys off the EXPLICIT choice, not the display fallback.
    expect(hook).toMatch(/if \(!chosenId \|\| topUpDoneFor === chosenId\) return;/);
  });

  it('the full standard reaches instances at runtime, not through the chain', () => {
    // The whole standard lives in the pack artifact, delivered by
    // topUpLocalePackSeeds / import_accounting_standard after activation.
    const packs = JSON.parse(
      readFileSync(join(__dirname, '../../../supabase/seed/locale-packs.json'), 'utf8'),
    );
    const se = packs.packs.find((p: any) => p.id === 'se-bas2024');
    expect(se?.accounts?.length ?? 0, 'the SE pack lost its chart').toBeGreaterThan(1000);

    // The chain may carry historical repairs, never a standard.
    const total = seeds.reduce((n, s) => n + s.codes.length, 0);
    expect(
      total,
      'the chain now carries more chart rows than the handful of historical\n' +
        'repairs — a standard is being smuggled in through migrations',
    ).toBeLessThan(40);
  });
});
