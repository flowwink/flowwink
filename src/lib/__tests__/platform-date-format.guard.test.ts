import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * CI guard for the platform DATE sweep (sibling of platform-format.guard.test.ts).
 *
 * Display components must render absolute dates through `usePlatformFormat()`
 * so they follow the instance's locale. Two classes of date-fns call are
 * offenders:
 *
 *  1. **English-shaped literals** — `'MMM d, yyyy'`, `'d MMM yyyy'`,
 *     `'EEEE, MMMM d, yyyy'`. These hardcode an American/English date shape on
 *     what may be a Swedish instance.
 *  2. **The P-family** — `'PP'`, `'PPP'`, `'PPp'`, `'PPpp'`. These are date-fns'
 *     *localized* tokens, so they LOOK correct in review — but with no `locale`
 *     option date-fns silently falls back to en-US. A latent bug that reads as
 *     intentional.
 *
 * Deliberately NOT offenders (locale-neutral or data, not display):
 *  - `'yyyy-MM-dd'` and `'yyyy-MM-dd HH:mm'` — ISO-shaped. Overwhelmingly query
 *    params, state defaults and API payloads; localizing those breaks queries.
 *  - `'HH:mm'` / `'HH:mm:ss'` — time-only, no locale-specific shape at stake.
 *  - `formatDistanceToNow` — relative time; a separate concern (date-fns locale).
 *
 * Same ratchet as the currency guard: PENDING can only shrink, and the sweep is
 * provably total when it reaches zero.
 */

const ALLOWED = [
  'src/hooks/usePlatformFormat.ts',
  'src/lib/format-currency.ts',
];

const PENDING_FILE = 'src/lib/__tests__/.date-sweep-pending.json';
const ROOTS = ['src/components', 'src/pages'];

// A date-fns pattern literal carrying a month-NAME or weekday-NAME token, or a
// P-family token ANYWHERE in the pattern. `[\s\S]{0,120}?` spans multi-line
// calls; the first arg often contains `new Date(...)`.
//
// The P-family alternative must not be anchored to the whole literal: a
// COMBINED pattern like 'PP HH:mm' is just as unlocalized as a bare 'PP', and
// an earlier version of this regex missed exactly that (ScheduleVisitDialog).
const OFFENDING =
  /\bformat\([\s\S]{0,120}?,\s*['"][^'"]*(?:\b(?:MMM|MMMM|EEE|EEEE)\b|(?<![A-Za-z])P{1,3}p{0,2}(?![A-Za-z]))[^'"]*['"]\s*\)/;

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

const pending: string[] = JSON.parse(readFileSync(PENDING_FILE, 'utf8'));

describe('platform date-formatting guard', () => {
  it('no NEW component hardcodes an English date shape or an unlocalized P-token', () => {
    const offenders = currentOffenders();
    const introduced = offenders.filter((f) => !pending.includes(f));
    expect(
      introduced,
      `Render absolute dates via usePlatformFormat() (formatDate/formatDateTime) in:\n${introduced.join('\n')}`,
    ).toEqual([]);
  });

  it('the pending-sweep list only shrinks', () => {
    const offenders = currentOffenders();
    const stale = pending.filter((f) => !offenders.includes(f));
    expect(
      stale,
      `These files are clean now — remove them from ${PENDING_FILE}:\n${stale.join('\n')}`,
    ).toEqual([]);
  });
});
