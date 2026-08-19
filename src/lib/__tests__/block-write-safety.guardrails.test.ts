import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  KNOWN_BLOCK_TYPES,
  DATA_DRIVEN_BLOCK_TYPES,
  normalizeBlockData,
  validateBlockData,
} from '../../../supabase/functions/_shared/normalize-blocks';
import { classifyCall, isReadSkill } from '../../../supabase/functions/_shared/skills/read-surface';
import { getImportableBlockTypes } from '@/lib/block-reference';

/**
 * Two QA agents wrote FlowWork pages end-to-end (2026-08-19) and found the
 * block write path forgiving in exactly the wrong places:
 *   (a) an INVENTED block type was written, saved and rendered as nothing;
 *   (b) an unknown FIELD answered "updated" and changed nothing;
 *   (c) validation ran BEFORE normalization, so the raw-string/alias
 *       forgiveness the normalizer offers never got a chance to apply.
 * These tests pin the fixed behaviour: the gate refuses what cannot render,
 * and the normalizer gets first pass at what merely has the wrong name.
 */

describe('block write safety — invented types are refused with suggestions', () => {
  it('rejects a type nothing renders, and names the near misses', () => {
    const result = validateBlockData('call_to_action', { title: 'X', buttonText: 'Go' });
    expect(result.valid).toBe(false);
    expect(result.errors.join(' ')).toContain('call_to_action');
    // The suggestion is the point: a bare "invalid" leaves the agent guessing.
    expect(result.errors.join(' ')).toContain('"cta"');
    // …and the full type list travels in the hint so a retry can pick blind.
    expect(result.hint).toContain('hero');
    expect(result.hint).toContain('describe_blocks');
  });

  it('suggests the FAQ-shaped blocks for the invented "faq" type', () => {
    const result = validateBlockData('faq', { items: [{ question: 'Q', answer: 'A' }] });
    expect(result.valid).toBe(false);
    const suggested = result.errors.join(' ');
    expect(suggested).toMatch(/accordion|ai-faq/);
  });

  it('accepts every renderable type — data-driven blocks are not "invented"', () => {
    // products/kb-hub/handbook render from the DB and are excluded from AI page
    // IMPORT, but adding one to a page is legitimate. Refusing them would be a
    // regression dressed as a fix.
    for (const type of DATA_DRIVEN_BLOCK_TYPES) {
      const result = validateBlockData(type, {});
      expect(result.valid, `${type} must be writable`).toBe(true);
    }
  });

  it('KNOWN_BLOCK_TYPES stays in sync with block-reference.ts', () => {
    // The Deno-side allowlist is IMPORTABLE_BLOCK_TYPES + the excluded list from
    // getImportableBlockTypes(). If someone edits that exclusion list, this fails.
    const src = readFileSync(join(process.cwd(), 'src/lib/block-reference.ts'), 'utf-8');
    const m = src.match(/const excluded = \[([^\]]+)\]/);
    expect(m, 'excluded list not found in block-reference.ts — update this parser').toBeTruthy();
    const excluded = [...m![1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
    expect([...DATA_DRIVEN_BLOCK_TYPES].sort()).toEqual([...excluded].sort());
    for (const type of getImportableBlockTypes()) {
      expect(KNOWN_BLOCK_TYPES, `${type} missing from the write gate`).toContain(type);
    }
  });
});

describe('block write safety — unknown fields are refused, not silently dropped', () => {
  it('names the offending field AND the valid field list', () => {
    const result = validateBlockData('hero', { title: 'Hello', tagline: 'nope' });
    expect(result.valid).toBe(false);
    const msg = result.errors.join(' ');
    expect(msg).toContain('tagline');
    expect(msg).toContain('unknown field');
    // The reply must carry the vocabulary, or the retry is another guess.
    expect(msg).toContain('subtitle');
    expect(msg).toContain('primaryButton');
  });

  it('internal "_"-prefixed keys are plumbing, not content', () => {
    const result = validateBlockData('hero', { title: 'Hello', _caller_user_id: 'u1' });
    expect(result.valid).toBe(true);
  });

  it('unknownFieldScope limits the check to what the caller sent', () => {
    // The update path merges stored data that may predate this gate. Judging the
    // merge would make such a block permanently un-editable by an agent.
    const merged = { title: 'Hello', legacyField: 'written in 2026-05' };
    expect(validateBlockData('hero', merged).valid).toBe(false);
    expect(
      validateBlockData('hero', merged, { unknownFieldScope: { title: 'New title' } }).valid,
    ).toBe(true);
  });
});

describe('block write safety — normalize runs BEFORE validate', () => {
  it('normalizeBlockData maps the hero aliases agents actually write', () => {
    const block = {
      id: 'b1',
      type: 'hero',
      data: { heading: 'Welcome', body: 'We build things', buttonText: 'Contact', buttonLink: '/contact' },
    };
    normalizeBlockData(block);
    const data = block.data as Record<string, unknown>;
    expect(data.title).toBe('Welcome');
    expect(data.subtitle).toBe('We build things');
    expect(data.primaryButton).toEqual({ text: 'Contact', url: '/contact' });
    // The wrong names must be gone — leaving them re-teaches the mistake and
    // trips the unknown-field gate on the next update.
    expect(data.heading).toBeUndefined();
    expect(data.body).toBeUndefined();
    expect(data.buttonText).toBeUndefined();
    expect(data.buttonLink).toBeUndefined();
  });

  it('a normalized hero passes the gate that its raw form would fail', () => {
    const raw = { heading: 'Welcome', buttonText: 'Contact', buttonLink: '/contact' };
    // Validated raw (the old order) → refused: no title, three unknown fields.
    expect(validateBlockData('hero', { ...raw }).valid).toBe(false);
    // Normalized first (the fixed order) → accepted.
    const block = { id: 'b1', type: 'hero', data: { ...raw } };
    normalizeBlockData(block);
    const result = validateBlockData('hero', block.data as Record<string, unknown>);
    expect(result.valid, result.errors.join('; ')).toBe(true);
  });

  it('text/two-column aliases and raw strings survive the round trip', () => {
    const text = { id: 't1', type: 'text', data: { heading: 'Title', text: 'Just a sentence.' } };
    normalizeBlockData(text);
    const td = text.data as Record<string, unknown>;
    expect(td.title).toBe('Title');
    expect((td.content as { type?: string })?.type).toBe('doc');
    expect(td.text).toBeUndefined();
    expect(validateBlockData('text', td).valid).toBe(true);

    const two = { id: 'c1', type: 'two-column', data: { leftContent: 'Left side', rightContent: 'Right side' } };
    normalizeBlockData(two);
    const cd = two.data as Record<string, unknown>;
    expect((cd.leftColumn as { type?: string })?.type).toBe('doc');
    expect((cd.rightColumn as { type?: string })?.type).toBe('doc');
    expect(cd.leftContent).toBeUndefined();
  });

  it('agent-execute normalizes before it validates on all three write paths', () => {
    const src = readFileSync(join(process.cwd(), 'supabase/functions/agent-execute/index.ts'), 'utf-8');
    const region = src.slice(src.indexOf("case 'manage_page_blocks'"), src.indexOf("case 'generate_meta_description'"));
    // Every validateBlockData call in the block-write region must be preceded by
    // a normalizeBlockData call — the ordering bug was invisible in review.
    const order = [...region.matchAll(/normalizeBlockData|validateBlockData/g)].map((m) => m[0]);
    expect(order.length).toBeGreaterThanOrEqual(6);
    let normalized = 0;
    for (const call of order) {
      if (call === 'normalizeBlockData') normalized++;
      else expect(normalized, 'validateBlockData ran before any normalizeBlockData').toBeGreaterThan(0);
    }
  });
});

describe('block write safety — the schema lookup is reachable from FlowWork', () => {
  it('describe_blocks counts as a read (it returns schema, touches no data)', () => {
    // Without this, an employee's "add a section to the pricing page" had to
    // guess field names: the loop could stage the write but never look up the
    // contract, because describe_* matches no read prefix.
    expect(isReadSkill('describe_blocks')).toBe(true);
    expect(classifyCall('describe_blocks', {})).toBe('read');
  });
});
