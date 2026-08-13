import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { resolveHeroHeight } from '../HeroBlock';

/**
 * Guardrail: no authored hero height renders as no height at all.
 *
 * heightMode is written by templates, agents and site imports — not only by the
 * editor's picker — so it arrives with values the renderer's lookup table never
 * anticipated. The table returned `undefined` for those, the section got no
 * min-height class, and a hero meant to fill 70% of the viewport collapsed to
 * text height. Two shipped platform pages (/processes, /use-cases) carried
 * '70vh' and looked stunted on the live marketing site for weeks; the editor
 * showed no selected height, the schema listed four values, and nothing warned.
 *
 * The class of bug is the silent no-op: an unknown value that produces neither
 * the requested behaviour nor an error. These tests pin the two halves of the
 * cure — arbitrary vh works, and anything else still gets a real height.
 */
describe('hero height resolution', () => {
  it('honours the named modes with a Tailwind class', () => {
    expect(resolveHeroHeight('viewport').className).toBe('min-h-screen');
    expect(resolveHeroHeight('80vh').className).toBe('min-h-[80vh]');
    expect(resolveHeroHeight('70vh').className).toBe('min-h-[70vh]');
    expect(resolveHeroHeight('60vh').className).toBe('min-h-[60vh]');
    expect(resolveHeroHeight('auto').className).toBe('py-24');
  });

  it('honours any other viewport height inline', () => {
    // Tailwind's JIT only emits classes it can read literally in source, so an
    // unnamed value cannot become a class — it becomes an inline min-height.
    expect(resolveHeroHeight('75vh')).toEqual({ className: undefined, style: { minHeight: '75vh' } });
    expect(resolveHeroHeight('100vh').style).toEqual({ minHeight: '100vh' });
    expect(resolveHeroHeight('45vh').style).toEqual({ minHeight: '45vh' });
  });

  it('never resolves to neither a class nor a style', () => {
    for (const mode of ['', 'tall', '0vh', '999vh', '80', '80px', 'min-h-screen', 'null']) {
      const r = resolveHeroHeight(mode);
      expect(r.className ?? r.style, `"${mode}" resolved to nothing — the silent no-op is back`).toBeTruthy();
    }
  });
});

describe('template heroes only use heights the renderer honours', () => {
  // The live bug did not come from a hand-edit; it came from a TEMPLATE, which
  // installs the same value onto every instance that picks it. Catching it at
  // the source is cheaper than catching it per site.
  const dir = join(process.cwd(), 'src/data/templates');
  const files = readdirSync(dir).filter((f) => f.endsWith('.ts') && f !== 'index.ts' && f !== 'types.ts');

  it('has templates to check', () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it('every authored heightMode resolves to a real height', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const src = readFileSync(join(dir, f), 'utf8');
      for (const m of src.matchAll(/heightMode:\s*'([^']*)'/g)) {
        const r = resolveHeroHeight(m[1]);
        if (!r.className && !r.style) offenders.push(`${f}: '${m[1]}'`);
      }
    }
    expect(
      offenders,
      `A template height the renderer cannot honour renders as no height at all.\n  ${offenders.join('\n  ')}`,
    ).toEqual([]);
  });
});
