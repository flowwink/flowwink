import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Guardrail: a style lookup in a public block must not be able to resolve to
 * nothing.
 *
 * Blocks index maps with authored data — `sizeClasses[data.size]`,
 * `HEIGHT_MAP[data.height]`. An unknown key yields `undefined`, and undefined
 * has two failure modes, both silent at author time:
 *
 *   • as a className it renders NO styling — a hero with no height, a marquee
 *     whose animation string is `marquee undefined linear infinite` (invalid,
 *     so it never moves), a grid whose class attribute literally reads
 *     "undefined"
 *   • as the base of a property access (`sizeClasses[size].icon`) it THROWS,
 *     and until BlockErrorBoundary existed that white-screened the whole page
 *
 * The sweep that followed the hero-height bug found 88 such lookups across 29
 * files. This test is what keeps the number at zero: any map declared as an
 * object literal in a block file, indexed by a non-literal key, must carry a
 * `??` or `||` fallback.
 *
 * Two exemptions, both legitimate:
 *   • maps with no static keys (accumulators built by spread — `next[fieldId]`
 *     in a form's state) are not style lookups at all
 *   • a lookup whose undefined is MEANINGFUL, marked with the comment marker
 *     below. resolveHeroHeight is the one: its undefined is what routes an
 *     unnamed value to the inline-vh branch, and an automated sweep that added
 *     a fallback there made the branch unreachable — this test caught it.
 */

const BLOCKS = join(process.cwd(), 'src/components/public/blocks');
const ALLOW_MARKER = 'deliberately NO';

function tsxFiles(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...tsxFiles(p));
    else if (e.name.endsWith('.tsx')) out.push(p);
  }
  return out;
}

/** First-level keys of `const NAME = { ... }`; empty when there are none. */
function mapKeys(src: string, name: string): string[] {
  const decl = new RegExp(`const\\s+${name}\\s*(?::\\s*[^=]+)?=\\s*\\{`).exec(src);
  if (!decl) return [];
  let depth = 1;
  let j = decl.index + decl[0].length;
  const start = j;
  while (j < src.length && depth > 0) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') depth--;
    j++;
  }
  const body = src.slice(start, j - 1);
  return [...body.matchAll(/(?:^|[,{]\s*)\s*(?:'([^']+)'|"([^"]+)"|([A-Za-z_]\w*)|(\d+))\s*:/g)].map(
    (m) => (m[1] ?? m[2] ?? m[3] ?? m[4]) as string,
  );
}

describe('block style lookups always resolve to something', () => {
  const files = tsxFiles(BLOCKS).filter((f) => !f.includes('__tests__'));

  it('has block files to check', () => {
    expect(files.length).toBeGreaterThan(50);
  });

  it('no map lookup is left without a fallback', () => {
    const offenders: string[] = [];

    for (const file of files) {
      const src = readFileSync(file, 'utf8');
      const maps = new Set([...src.matchAll(/const\s+([A-Za-z_]\w*)\s*(?::\s*[^=]+)?=\s*\{/g)].map((m) => m[1]));

      for (const name of maps) {
        // No static keys → an accumulator, not a style table.
        if (mapKeys(src, name).length === 0) continue;

        for (const use of src.matchAll(new RegExp(`\\b${name}\\[`, 'g'))) {
          let depth = 1;
          let j = use.index! + use[0].length;
          const keyStart = j;
          while (j < src.length && depth > 0) {
            if (src[j] === '[') depth++;
            else if (src[j] === ']') depth--;
            j++;
          }
          const key = src.slice(keyStart, j - 1).trim();
          // Literal keys are checked by the compiler, not by data.
          if (/^\d+$/.test(key) || key.startsWith("'") || key.startsWith('"')) continue;
          if (/^\s*(\?\?|\|\|)/.test(src.slice(j, j + 40))) continue;

          const line = src.slice(0, use.index!).split('\n').length;
          const context = src.split('\n').slice(Math.max(0, line - 6), line).join('\n');
          if (context.includes(ALLOW_MARKER)) continue;

          offenders.push(`${file.replace(process.cwd() + '/', '')}:${line} → ${name}[${key.slice(0, 30)}]`);
        }
      }
    }

    expect(
      offenders,
      'An unguarded lookup renders as no styling, or throws when a property is read\n' +
        `off it. Write \`${'MAP[key] ?? MAP.default'}\`, or explain the deliberate undefined\n` +
        `in a comment containing "${ALLOW_MARKER}".\nOffenders:\n  ${offenders.join('\n  ')}`,
    ).toEqual([]);
  });
});
