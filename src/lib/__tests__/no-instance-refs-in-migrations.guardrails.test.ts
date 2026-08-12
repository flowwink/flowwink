import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/**
 * A migration cannot know which instance it will run on.
 *
 * So anything it writes containing a project URL is correct for exactly one
 * instance — the one it was authored against — and wrong for every other. This
 * has now happened twice, both times silently, both times leaving production
 * instances talking to our development project:
 *
 *   • 20260707022750 baked dev's URL into the newsletter cron. The whole fleet
 *     dispatched scheduled newsletters against DEV's data for eleven days
 *     (fixed 20260718090000).
 *   • 20260704152107 baked dev's URL *and anon key* into
 *     trigger_score_visitor_intent. Every customer's lead flow POSTed to dev on
 *     every identified lead; scoring never ran anywhere. Still present on two
 *     production instances when found on 2026-08-12 (fixed 20260812180000).
 *
 * Neither was caught by review, because in a diff a project URL looks like
 * configuration rather than a defect. This test is the reviewer that does not
 * get used to it.
 *
 * The remedy in both fixes is the same and is what new code should copy: derive
 * the instance's own host and key at RUNTIME from the `knowledge-indexer` cron
 * job, which every instance registers with its own identity — and post nowhere
 * if that lookup fails. Sending nowhere beats sending to us.
 */

const MIGRATIONS = join(__dirname, '../../../supabase/migrations');

/** `<20-char-ref>.supabase.co` — the shape of a Supabase project URL. */
const PROJECT_URL = /\b[a-z0-9]{20}\.supabase\.co/g;
/** A JWT literal: an anon/service key pasted into SQL. */
const JWT_LITERAL = /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g;

/** Strip `--` comments: the fixes DESCRIBE the bad URLs to explain themselves. */
const codeOnly = (sql: string) => sql.replace(/--[^\n]*/g, '');

/**
 * The one file still carrying a project URL, and why it may.
 *
 * 20260707022750 SCHEDULES the newsletter cron. A cron command needs a URL at
 * the moment it is written, and SQL has no way to ask which instance it is on —
 * only the edge runtime knows that, which is why `knowledge-indexer` is the
 * thing every other job borrows its identity from. Rewriting this one to derive
 * its URL would mean not scheduling at all on a fresh install (no template job
 * exists yet at that point in the replay), i.e. trading a wrong URL for no
 * newsletter dispatch. It is already self-healed on the live fleet by
 * 20260718090000, verified 2026-08-12: no cron job on any instance points
 * anywhere but at itself.
 *
 * The real repair is to let the newsletter cron self-register from the edge
 * runtime the way knowledge-indexer does. Until then this stays listed — one
 * named exception with a reason, not a silenced rule.
 */
const KNOWN_EXCEPTIONS = new Set(['20260707022750_5947e018-0987-476f-a8cb-d51ea4be3ed7.sql']);

const files = readdirSync(MIGRATIONS)
  .filter((f) => f.endsWith('.sql'))
  .filter((f) => !KNOWN_EXCEPTIONS.has(f));

describe('no migration hardcodes a specific instance', () => {
  it('has migrations to check', () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it('contains no project URL in executable SQL', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const matches = codeOnly(readFileSync(join(MIGRATIONS, f), 'utf-8')).match(PROJECT_URL);
      if (matches) offenders.push(`${f} → ${[...new Set(matches)].join(', ')}`);
    }
    expect(
      offenders,
      'A migration runs on every instance; a project URL in one is right for at most one of them.\n' +
        'Derive host+key at runtime from the knowledge-indexer cron job instead — see\n' +
        'supabase/migrations/20260812180000_leads-score-on-its-own-instance.sql.\n' +
        `Offenders:\n  ${offenders.join('\n  ')}`,
    ).toEqual([]);
  });

  it('contains no API key literal in executable SQL', () => {
    // dev's anon key sat in plain text inside every customer's database for
    // five weeks because it was pasted into a function body.
    const offenders: string[] = [];
    for (const f of files) {
      const matches = codeOnly(readFileSync(join(MIGRATIONS, f), 'utf-8')).match(JWT_LITERAL);
      if (matches) offenders.push(`${f} → ${matches.length} key literal(s)`);
    }
    expect(
      offenders,
      'A key pasted into a migration is copied into every instance that replays it.\n' +
        `Offenders:\n  ${offenders.join('\n  ')}`,
    ).toEqual([]);
  });
});
