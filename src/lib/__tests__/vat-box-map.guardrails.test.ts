import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { SE_VAT_RETURN_2026 } from '../locale-packs/se/vat-return-2026';

/**
 * Guardrail: the VAT return's SQL account buckets must match the declarative
 * box map in the locale pack.
 *
 * This drift caused a real, material bug (found 2026-07-25 on live data):
 * `prepare_vat_return` summed account **2611** as "reverse charge". 2611 is
 * *Utgående moms på försäljning INOM Sverige, 25%* — an unrelated account.
 * Meanwhile the pack maps reverse charge to 2614/2615. Consequence: a
 * reverse-charge purchase booked its input VAT (2645, box 48) but its output
 * leg was invisible, so the return claimed a refund the company was not owed.
 * The rate buckets had the mirror problem — they read a single account each
 * (2610/2620/2630), so ordinary sales booked to 2611/2621/2631 vanished.
 *
 * Two sources of truth for the same mapping is the hazard; until the box map
 * lives in one place both SQL and TS read, this test is the seam.
 */

const MIGRATION = 'supabase/migrations/20260726090000_reverse-charge-vat.sql';
const sql = readFileSync(join(process.cwd(), MIGRATION), 'utf8');

/** Accounts the pack assigns to a box. */
function packAccounts(code: string): string[] {
  const box = SE_VAT_RETURN_2026.boxes.find((b) => b.code === code) as
    | { accounts?: string[] }
    | undefined;
  return [...(box?.accounts ?? [])].sort();
}

/** Account codes inside the Nth `IN (...)` list of the prepare_vat_return body. */
function sqlBuckets(): string[][] {
  const fn = sql.slice(sql.indexOf('FUNCTION public.prepare_vat_return'));
  return [...fn.matchAll(/account_code IN \(([^)]*)\)/g)].map((m) =>
    [...m[1].matchAll(/'(\d{4})'/g)].map((x) => x[1]).sort(),
  );
}

/**
 * The box map used to exist TWICE — once in the pack, once duplicated inside the
 * Deno edge handler (which cannot import from src/). They drifted, and the drift
 * shipped bugs: 2611 counted as reverse charge, and box 21 mixing EU with non-EU
 * service purchases. It now lives in exactly one import-free file that both
 * runtimes read. These tests defend that singularity.
 */
describe('VAT box map — exactly one copy', () => {
  const handler = readFileSync(
    join(process.cwd(), 'supabase/functions/_shared/handlers/accounting-vat-return-se.ts'),
    'utf8',
  );

  it('the handler IMPORTS the map instead of declaring its own', () => {
    expect(handler).toMatch(/import \{[^}]*SE_VAT_BOXES_2026[^}]*\} from '\.\.\/locale\/se-vat-boxes\.ts'/);
    expect(
      handler.match(/code:\s*'\d+'/g) ?? [],
      'the handler declares box definitions again — that is the duplication this replaced',
    ).toHaveLength(0);
  });

  it('the shared map has no imports, which is what lets both runtimes read it', () => {
    const shared = readFileSync(
      join(process.cwd(), 'supabase/functions/_shared/locale/se-vat-boxes.ts'),
      'utf8',
    );
    expect(
      shared.match(/^import /m),
      'an import here breaks either the Deno side or the Vite side',
    ).toBeNull();
  });

  it('EU and non-EU service purchases are separate boxes (21 vs 22)', () => {
    const box = (c: string) =>
      (SE_VAT_RETURN_2026.boxes as Array<{ code: string; accounts?: string[] }>)
        .find((b) => b.code === c)?.accounts ?? [];
    // 4531-4534 are OUTSIDE the EU; in box 21 they report a US purchase as an
    // EU acquisition — the bug this split fixes.
    expect(box('21')).not.toContain('4531');
    expect(box('22')).toContain('4531');
    expect(box('21')).toContain('4535');
  });
});

describe('VAT return box map — SQL matches the locale pack', () => {
  it('extracts four buckets from the SQL (25 / 12 / 6 / reverse, then input)', () => {
    expect(sqlBuckets().length).toBe(5);
  });

  it('output VAT buckets 25/12/6 match boxes 10/11/12', () => {
    const [b25, b12, b6] = sqlBuckets();
    expect(b25).toEqual(packAccounts('10'));
    expect(b12).toEqual(packAccounts('11'));
    expect(b6).toEqual(packAccounts('12'));
  });

  it('the reverse-charge bucket is boxes 30+31+32 — and never 2611', () => {
    const reverse = sqlBuckets()[3];
    const expected = [...packAccounts('30'), ...packAccounts('31'), ...packAccounts('32')].sort();
    expect(reverse).toEqual(expected);
    expect(
      reverse,
      '2611 is domestic 25% output VAT, not reverse charge — this was the original bug',
    ).not.toContain('2611');
  });

  it('the input bucket matches box 48', () => {
    expect(sqlBuckets()[4]).toEqual(packAccounts('48'));
  });

  it('every account the reverse-charge boxes reference is created by the migration', () => {
    const needed = [...packAccounts('30'), ...packAccounts('31'), ...packAccounts('32')];
    const created = [...sql.matchAll(/\('(\d{4})',\s*'[^']*',\s*'(?:liability|asset)'/g)].map((m) => m[1]);
    for (const code of needed) {
      expect(created, `account ${code} is referenced by a VAT box but never seeded`).toContain(code);
    }
  });

  it('reverse charge is DECLARED on the expense, never inferred (Law 1)', () => {
    expect(sql).toMatch(/reverse_charge_rate/);
    // The rate drives the booking; nothing may branch on currency or vendor.
    const fn = sql.slice(sql.indexOf('FUNCTION public.book_expense_report'));
    expect(fn, 'must not infer reverse charge from the currency').not.toMatch(/currency\s*(<>|!=|=)\s*'/);
    expect(fn, 'must not infer reverse charge from the vendor').not.toMatch(/vendor\s*(ILIKE|LIKE|=)/);
  });

  it('resolves accounts through roles, not hardcoded numbers, when booking', () => {
    const fn = sql.slice(
      sql.indexOf('FUNCTION public.book_expense_report'),
      sql.indexOf('FUNCTION public.prepare_vat_return'),
    );
    expect(fn).toMatch(/vat_output_reverse_/);
    expect(fn).toMatch(/vat_input_reverse/);
    // A locale with no such role must skip, not invent an account.
    expect(fn).toMatch(/reverse_charge_skipped/);
  });
});
