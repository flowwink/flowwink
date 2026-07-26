import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Guardrail: how `sync-skills --prune` retires an orphan.
 *
 * The root cause it fixes: sync inserted and updated but never retired, so a
 * skill deleted from the seeds lived on every instance forever. That is how two
 * generations of QA skills ended up side by side (openclaw_start_session &c.
 * next to start_qa_session &c.) — the same capability under two names, doubling
 * the MCP surface and making the relevance engine rank near-identical entries
 * against each other.
 *
 * Retiring is destructive-adjacent, so its safety properties are asserted here
 * rather than trusted:
 *   1. disable, never DELETE — the row carries trust overrides and history, an
 *      agent may hold the name in a plan, and disable is reversible.
 *   2. leave recently-used orphans alone — recent use means the SEED is wrong,
 *      not the instance, and silently disabling a live skill would break it.
 *   3. dry-run by default — the flag reports; only --apply writes.
 */

const src = readFileSync(join(process.cwd(), 'scripts/sync-skills.ts'), 'utf8');
/** Strip comments: the file explains the rules in prose that quotes them. */
const code = src
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n')
  .filter((l) => !l.trimStart().startsWith('//') && !l.trimStart().startsWith('*'))
  .join('\n');

describe('sync-skills --prune', () => {
  it('retires by disabling and never issues a DELETE', () => {
    expect(code).toMatch(/update agent_skills set enabled = false, mcp_exposed = false/);
    expect(
      code,
      'a deleted skill row cannot be restored — retire by disabling',
    ).not.toMatch(/delete\s+from\s+agent_skills/i);
  });

  it('spares an orphan that was used recently', () => {
    expect(code).toMatch(/PRUNE_QUIET_DAYS/);
    expect(code).toMatch(/quietFor\s*<\s*PRUNE_QUIET_DAYS/);
    // It must be reported, not silently ignored — a used orphan is a seed bug.
    expect(code).toMatch(/keptRecent/);
  });

  it('writes only under --apply, and pruning is opt-in', () => {
    expect(code).toMatch(/const PRUNE = process\.argv\.includes\('--prune'\)/);
    // The disabling UPDATE must sit behind the APPLY gate.
    const pruneBlock = code.slice(code.indexOf('if (PRUNE)'));
    const update = pruneBlock.indexOf('update agent_skills set enabled = false');
    const apply = pruneBlock.indexOf('if (APPLY)');
    expect(apply, 'no APPLY gate found before the write').toBeGreaterThan(-1);
    expect(apply, 'the retiring UPDATE must be inside the APPLY branch').toBeLessThan(update);
  });

  it('treats a skill from a disabled module as dormant, not orphaned', () => {
    // Orphan = absent from the ARTIFACT entirely. Filtering by isEnabled here
    // would retire every skill of a module the customer has merely switched off.
    const pruneBlock = code.slice(code.indexOf('if (PRUNE)'));
    expect(pruneBlock).toMatch(/for \(const m of modules\) for \(const s of m\.skills\) seeded\.add/);
    expect(
      pruneBlock.slice(0, pruneBlock.indexOf('const { rows: orphans }')),
      'orphan detection must not consult isEnabled',
    ).not.toMatch(/isEnabled/);
  });
});
