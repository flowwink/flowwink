import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Guardrail: every enum-ish value a template authors must be one the block
 * schema declares — and therefore one the renderer knows.
 *
 * The failure this generalises was found in HeroBlock: `heightMode: '70vh'`,
 * written by a template, looked up in a map that had no such key, resolved to
 * `undefined`, and produced a hero with no height. Nothing warned. Sweeping the
 * same question across every block and every template turned one bug into
 * twelve, three of which were visibly broken rather than merely off-style:
 *
 *   • announcement-bar variant='default'  → no background, no text colour
 *   • marquee speed='medium'              → `animation: marquee undefined` —
 *                                           invalid CSS, the marquee never moved
 *   • two-column imageRounded='xl'        → no corner radius at all
 *
 * The other nine were the schema understating its own renderer (badge variants,
 * floating-cta positions, logos layouts), which is its own defect: the schema is
 * what an agent reads before authoring a page, so a stale option list teaches
 * agents to avoid capabilities that exist.
 *
 * Renderers now fall back rather than render nothing. This test closes the
 * other half: it fails at authoring time, in CI, before anything ships.
 */

const ROOT = process.cwd();

/** Parse `options: [...]` per block type out of the canonical registry. */
function schemaOptions(): Record<string, Record<string, Set<string>>> {
  const src = readFileSync(join(ROOT, 'src/lib/block-reference.ts'), 'utf8');
  const out: Record<string, Record<string, Set<string>>> = {};
  let current: string | null = null;
  for (const line of src.split('\n')) {
    // A block entry's own `type:` sits at four-space indent; prop definitions
    // carry `name:` on the same line and must not be mistaken for one.
    const block = /^\s{4}type:\s*'([a-z0-9-]+)'/.exec(line);
    if (block) current = block[1];
    const prop = /\{\s*name:\s*'(\w+)'.*?options:\s*\[([^\]]+)\]/.exec(line);
    if (prop && current) {
      (out[current] ??= {})[prop[1]] = new Set(
        prop[2].split(',').map((v) => v.trim().replace(/^['"]|['"]$/g, '')),
      );
    }
  }
  return out;
}

interface Block { type?: string; data?: Record<string, unknown> }

describe('authored block values stay inside the schema', () => {
  const options = schemaOptions();
  const templates = JSON.parse(
    readFileSync(join(ROOT, 'supabase/functions/agent-execute/_templates.json'), 'utf8'),
  ) as Record<string, Record<string, unknown>>;

  it('parses the registry', () => {
    expect(Object.keys(options).length).toBeGreaterThan(30);
  });

  it('has templates to check', () => {
    expect(Object.keys(templates).length).toBeGreaterThan(5);
  });

  it('every template block value is one the schema declares', () => {
    const offenders: string[] = [];

    const visit = (blocks: unknown, templateId: string) => {
      if (!Array.isArray(blocks)) return;
      for (const b of blocks as Block[]) {
        if (!b || typeof b !== 'object' || !b.type) continue;
        const props = options[b.type];
        if (!props) continue;
        for (const [prop, allowed] of Object.entries(props)) {
          const v = (b.data ?? {})[prop];
          if (typeof v === 'string' && !allowed.has(v)) {
            offenders.push(
              `${templateId}: ${b.type}.${prop}='${v}' (schema allows: ${[...allowed].sort().join(', ')})`,
            );
          }
        }
      }
    };

    for (const [id, t] of Object.entries(templates)) {
      if (!t || typeof t !== 'object') continue;
      for (const page of (t.pages as { blocks?: unknown }[] | undefined) ?? []) visit(page?.blocks, id);
      for (const key of ['globalBlocks', 'footerBlocks', 'headerBlocks']) visit(t[key], id);
    }

    expect(
      [...new Set(offenders)],
      'A value outside the schema is a value the renderer may not know — and an unknown\n' +
        'key resolves to undefined, which renders as nothing rather than as an error.\n' +
        'Either author a declared value, or extend BOTH the renderer and the schema.\n' +
        `Offenders:\n  ${[...new Set(offenders)].join('\n  ')}`,
    ).toEqual([]);
  });
});
