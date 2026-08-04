import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Two things a visitor sees on every page that no page-level test covers: the
 * cookie banner and the hero's background video. Both were caught by looking at
 * a screenshot of optic, not by reading the DOM text — text assertions pass
 * happily on a banner that says the wrong thing in the wrong language.
 */

const read = (p: string) => readFileSync(resolve(__dirname, '../..', p), 'utf-8');

describe('cookie banner copy is data, not code', () => {
  const src = read('components/public/CookieBanner.tsx');
  // Everything from the component onward is render code; the defaults object
  // above it is where the English is allowed to live.
  const render = src.slice(src.indexOf('export function CookieBanner'));

  /**
   * The category labels were configurable while the title, body and buttons
   * were hardcoded English — so optic, a Swedish site whose entire pitch is
   * GDPR and data sovereignty, greeted visitors with "We use cookies". Copy is
   * data so an operator (or an agent over the gateway) can translate it.
   */
  for (const phrase of [
    'We use cookies',
    'Accept all',
    'Essential only',
    'Save selection',
    'Cookie preferences',
  ]) {
    it(`does not hardcode "${phrase}" in the rendered banner`, () => {
      expect(
        render.includes(phrase),
        `"${phrase}" is baked into the JSX — read it from site_settings.cookie_consent_v2.text instead`,
      ).toBe(false);
    });
  }

  it('every default string has a settings path', () => {
    expect(src).toContain('const defaultText: BannerText');
    expect(src).toContain('...(settings.text ?? {})');
  });
});

describe('hero background video is decor, not a player', () => {
  const src = read('components/public/blocks/HeroBlock.tsx');
  const iframes = [...src.matchAll(/<iframe[\s\S]*?\/>/g)].map((m) => m[0]);

  it('finds the background embeds', () => {
    expect(iframes.length).toBeGreaterThan(0);
  });

  /**
   * A background video with pointer events lets a visitor click it, which
   * pauses playback — and a paused YouTube embed draws its own title bar over
   * the hero headline ("Cyberpunk Code Hacker Glitch Hi-Tech Background
   * video…" sat above "Suveränitet börjar i marken"). `showinfo=0` has been
   * ignored by YouTube since 2018, so the param list cannot prevent it.
   */
  for (const [i, frame] of iframes.entries()) {
    const isBackground = frame.includes('controls=0') || frame.includes('background=1');
    if (!isBackground) continue;
    it(`background iframe ${i + 1} cannot be clicked or paused`, () => {
      expect(
        frame.includes('pointer-events-none'),
        'a clickable background video can be paused, which reveals the provider\'s title overlay',
      ).toBe(true);
    });
  }
});
