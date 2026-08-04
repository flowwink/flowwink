import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { BLOCK_REFERENCE } from '../block-reference';

/**
 * The block registry is what agents read. The renderer is what users see.
 * When they drift, an agent composes with the documented subset and the pages
 * come out as the poor cousin of what the block can do — two-column carried 23
 * fields (eyebrow, script-font accent, image aspect/fit, sticky column…) while
 * the registry documented 4, so gateway-composed pages used 4.
 *
 * This compares, per block, the fields the public renderer actually reads
 * (`data.X`) against the fields the registry documents. Blocks in PENDING are
 * known-stale and tolerated; the list only shrinks. Fix a block's registry
 * entry, remove it from PENDING, and drift can never silently return for it.
 * (Same shrinking-pending-list pattern as the currency and date sweeps.)
 */

const rendererDir = resolve(__dirname, '../../components/public/blocks');

/** kebab-case type → PascalCaseBlock.tsx, the repo's naming convention. */
function rendererPath(type: string): string | null {
  const pascal = type.split('-').map((s) => s[0].toUpperCase() + s.slice(1)).join('');
  const p = resolve(rendererDir, `${pascal}Block.tsx`);
  return existsSync(p) ? p : null;
}

/** Fields the renderer reads off `data.` — its true consumption surface. */
function rendererFields(path: string): Set<string> {
  const src = readFileSync(path, 'utf-8');
  const fields = new Set<string>();
  for (const m of src.matchAll(/\bdata\.([a-zA-Z][a-zA-Z0-9]*)\b/g)) fields.add(m[1]);
  return fields;
}

/**
 * Not yet audited — documented subset is known to be smaller than the renderer.
 * SHRINK ONLY. Adding a block here is admitting new drift; do that in a commit
 * that says why, or better, fix the registry entry instead.
 */
const PENDING = new Set([
  'hero', 'text', 'image', 'cta', 'contact', 'link-grid', 'info-box',
  'accordion', 'article-grid', 'latest-posts', 'youtube', 'quote', 'separator',
  'gallery', 'stats', 'chat', 'map', 'form', 'newsletter', 'popup', 'booking',
  'pricing', 'testimonials', 'team', 'logos', 'comparison', 'features',
  'timeline', 'tabs', 'marquee', 'embed', 'lottie', 'table', 'countdown',
  'progress', 'badge', 'social-proof', 'notification-toast', 'floating-cta',
  'chat-launcher', 'webinar', 'parallax-section', 'bento-grid',
  'section-divider', 'featured-carousel', 'trust-bar', 'category-nav',
  'shipping-info', 'ai-assistant', 'quick-links', 'sticky-scroll', 'ai-faq',
  'pricing-calculator', 'announcement-bar', 'products', 'cart', 'smart-booking',
]);

describe('block registry documents what the renderer can do', () => {
  const audited = BLOCK_REFERENCE.filter(
    (b) => !PENDING.has(b.type) && rendererPath(b.type),
  );

  it('audits at least the blocks fixed so far', () => {
    expect(audited.map((b) => b.type)).toContain('two-column');
  });

  for (const block of audited) {
    it(`${block.type}: no renderer field is missing from the registry`, () => {
      const path = rendererPath(block.type)!;
      const consumed = rendererFields(path);
      const documented = new Set(block.fields.map((f) => f.name));
      const undocumented = [...consumed].filter((f) => !documented.has(f)).sort();
      expect(
        undocumented,
        `${block.type}'s renderer reads fields the registry does not document — ` +
          `agents composing from the registry cannot use them:\n  ${undocumented.join(', ')}`,
      ).toEqual([]);
    });
  }

  it('PENDING only shrinks: no audited block is re-added', () => {
    // A block cannot be both audited-clean and pending; if a future edit re-adds
    // a fixed block to PENDING, this fails and the regression is loud.
    for (const b of audited) expect(PENDING.has(b.type)).toBe(false);
  });
});
