import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

/**
 * `.env.example` is the only checklist someone has when standing up a new
 * instance, and it drifts silently: nothing fails when a new secret is added and
 * the file is not, so the gap only surfaces as a feature that runs and quietly
 * does nothing. It had accumulated 33 undocumented secrets that way — including
 * RESEND_API_KEY, without which the system sends no mail at all and says
 * nothing about it.
 *
 * These assert both directions. A documented name that no longer exists is as
 * misleading as a missing one: it sends an operator to configure something the
 * code stopped reading.
 */

const root = resolve(__dirname, '../../..');
const envExample = readFileSync(join(root, '.env.example'), 'utf-8');

/** Supabase injects these into every function; documenting them invites confusion. */
const AUTO_PROVIDED = new Set([
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_DB_URL',
]);

/**
 * Read by exactly one function, and only as a backward-compatible alias for
 * PUBLIC_SITE_URL. Documenting it would undo the consolidation.
 */
const DELIBERATELY_UNDOCUMENTED = new Set(['SITE_URL']);

/**
 * `.tsx` as well as `.ts` — this guard's own first run missed
 * VITE_SUPABASE_PROJECT_ID because it is referenced only from components, and
 * reported the file as over-documenting a variable that is very much in use.
 */
function walk(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (entry.endsWith('.ts') || entry.endsWith('.tsx')) out.push(full);
  }
  return out;
}

function secretsReadByFunctions(): Set<string> {
  const found = new Set<string>();
  for (const file of walk(join(root, 'supabase/functions'))) {
    const src = readFileSync(file, 'utf-8');
    for (const m of src.matchAll(/Deno\.env\.get\(['"]([A-Z_0-9]+)['"]\)/g)) {
      const name = m[1];
      if (!AUTO_PROVIDED.has(name) && !name.startsWith('VITE_') && !name.startsWith('DENO_')) {
        found.add(name);
      }
    }
  }
  return found;
}

/** Names the file documents, whether commented out or live. */
function documentedNames(): Set<string> {
  return new Set(
    [...envExample.matchAll(/^#?\s*([A-Z_0-9]+)=/gm)].map((m) => m[1]),
  );
}

describe('.env.example covers every secret the functions read', () => {
  it('documents all of them', () => {
    const documented = documentedNames();
    const missing = [...secretsReadByFunctions()]
      .filter((n) => !documented.has(n) && !DELIBERATELY_UNDOCUMENTED.has(n))
      .sort();

    expect(
      missing,
      `Secrets read by edge functions but absent from .env.example. A new install ` +
        `has no way to know these exist, and an unset secret usually degrades ` +
        `silently rather than erroring:\n  ${missing.join('\n  ')}`,
    ).toEqual([]);
  });

  it('documents nothing the code stopped reading', () => {
    const read = secretsReadByFunctions();
    const stale = [...documentedNames()]
      .filter((n) => !read.has(n) && !n.startsWith('VITE_') && !AUTO_PROVIDED.has(n))
      .sort();

    expect(
      stale,
      `Documented in .env.example but no longer read anywhere. Sends an operator ` +
        `to configure something that does nothing:\n  ${stale.join('\n  ')}`,
    ).toEqual([]);
  });
});

describe('the frontend section matches what src/ actually reads', () => {
  function frontendVarsInCode(): Set<string> {
    const found = new Set<string>();
    for (const file of walk(join(root, 'src'))) {
      for (const m of readFileSync(file, 'utf-8').matchAll(/import\.meta\.env\.(VITE_[A-Z_]+)/g)) {
        found.add(m[1]);
      }
    }
    return found;
  }

  it('lists exactly the VITE_ vars the app uses — no more, no fewer', () => {
    const documented = [...documentedNames()].filter((n) => n.startsWith('VITE_')).sort();
    expect(documented).toEqual([...frontendVarsInCode()].sort());
  });

  it('warns that Vite inlines them at build time', () => {
    // The commonest deployment surprise: change the var, redeploy the same
    // artifact, and the app still points at the old project.
    expect(envExample).toMatch(/build time/i);
  });
});

describe('the PUBLIC_SITE_URL consolidation holds', () => {
  it('documents PUBLIC_SITE_URL and not the legacy SITE_URL as a thing to set', () => {
    expect(documentedNames()).toContain('PUBLIC_SITE_URL');
    expect(documentedNames()).not.toContain('SITE_URL');
  });

  it('leaves the one legacy reader accepting both', () => {
    const cb = readFileSync(
      join(root, 'supabase/functions/gmail-oauth-callback/index.ts'),
      'utf-8',
    );
    expect(cb).toMatch(/get\('PUBLIC_SITE_URL'\)[\s\S]{0,60}get\('SITE_URL'\)/);
  });

  it('has no other function still reading SITE_URL alone', () => {
    const offenders = walk(join(root, 'supabase/functions'))
      .filter((f) => !f.endsWith('gmail-oauth-callback/index.ts'))
      .filter((f) => /Deno\.env\.get\(['"]SITE_URL['"]\)/.test(readFileSync(f, 'utf-8')))
      .map((f) => f.replace(root + '/', ''));
    expect(offenders, 'these should read PUBLIC_SITE_URL').toEqual([]);
  });
});
