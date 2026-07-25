import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * CI guard for the platform-formatting sweep.
 *
 * Display components must format money/dates through `usePlatformFormat()`.
 * Raw `Intl.NumberFormat` / `Intl.DateTimeFormat` calls, hardcoded `en-US`
 * locales and hardcoded `currency: 'USD'` are only allowed inside the
 * formatting primitives themselves.
 *
 * NOTE: this starts as an allowlist of the files that are already migrated.
 * The follow-up app-wide sweep shrinks `PENDING_SWEEP` to zero — when the list
 * is empty the sweep is provably total.
 */

const ALLOWED = [
  'src/hooks/usePlatformFormat.ts',
  'src/lib/format-currency.ts',
  // Renders API-documentation code samples, not money. The `currency: "USD"`
  // inside those samples is documentation text — rewriting it to satisfy this
  // guard would corrupt the docs to please a lint rule.
  'src/components/admin/modules/ModuleDetailSheet.tsx',
];

// Files still carrying legacy formatting. Do NOT add to this list — remove
// entries as they are migrated to usePlatformFormat().
const PENDING_SWEEP_SNAPSHOT_FILE = 'src/lib/__tests__/.format-sweep-pending.json';

const ROOTS = ['src/components', 'src/pages'];
const OFFENDING = /new Intl\.(NumberFormat|DateTimeFormat)|toLocaleString\(\s*['"]en-US|currency:\s*['"]USD['"]/;

function walk(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.tsx?$/.test(full) && !/\.test\.tsx?$/.test(full)) out.push(full);
  }
  return out;
}

function currentOffenders(): string[] {
  const files: string[] = [];
  for (const root of ROOTS) walk(root, files);
  return files
    .filter((f) => !ALLOWED.includes(f.replace(/\\/g, '/')))
    .filter((f) => OFFENDING.test(readFileSync(f, 'utf8')))
    .map((f) => f.replace(/\\/g, '/'))
    .sort();
}

const pending: string[] = JSON.parse(readFileSync(PENDING_SWEEP_SNAPSHOT_FILE, 'utf8'));

describe('platform formatting guard', () => {
  it('no NEW component introduces raw Intl / en-US / hardcoded USD formatting', () => {
    const offenders = currentOffenders();
    const introduced = offenders.filter((f) => !pending.includes(f));
    expect(
      introduced,
      `Use usePlatformFormat() instead of raw Intl/en-US/USD formatting in:\n${introduced.join('\n')}`,
    ).toEqual([]);
  });

  it('the pending-sweep list only shrinks', () => {
    const offenders = currentOffenders();
    const staleEntries = pending.filter((f) => !offenders.includes(f));
    expect(
      staleEntries,
      `These files are clean now — remove them from ${PENDING_SWEEP_SNAPSHOT_FILE}:\n${staleEntries.join('\n')}`,
    ).toEqual([]);
  });
});
