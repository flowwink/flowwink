import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * describe_blocks — the block vocabulary, served to whoever asks.
 *
 * The finding (#173): manage_page_blocks' instructions say "when unsure what a
 * block supports, ask for its schema rather than guessing from examples" — and
 * there was no skill to ask. BLOCK_TYPES_SCHEMA reached FlowPilot through its
 * prompt (cms-context) but the gateway exposed it nowhere, so FlowPilot saw the
 * vocabulary and every external agent guessed. That is precisely the asymmetry
 * the contract authoring guide does not have.
 */

const handler = readFileSync(
  resolve(__dirname, '../../../supabase/functions/_shared/handlers/describe-blocks.ts'), 'utf-8');
const seeds = readFileSync(resolve(__dirname, '../../../src/lib/platform-seeds.ts'), 'utf-8');
const agentExecute = readFileSync(
  resolve(__dirname, '../../../supabase/functions/agent-execute/index.ts'), 'utf-8');
const pagesModule = readFileSync(
  resolve(__dirname, '../../../src/lib/modules/pages-module.ts'), 'utf-8');

const seed = seeds.slice(seeds.indexOf("name: 'describe_blocks'"), seeds.indexOf("name: 'check_integrations'"));

describe('it is a PLATFORM primitive, not a pages-module feature', () => {
  it('lives in platform-seeds so an external operator has it with FlowPilot off', () => {
    expect(seeds).toMatch(/name: 'describe_blocks'/);
    expect(pagesModule).not.toMatch(/name: 'describe_blocks'/);
  });

  it('is wired as an internal handler in agent-execute', () => {
    expect(seed).toMatch(/handler: 'internal:describe_blocks'/);
    expect(agentExecute).toMatch(/handler === 'internal:describe_blocks'/);
    expect(agentExecute).toMatch(/import \{ executeDescribeBlocks \}/);
  });

  it('is free to call — a reference lookup must never be gated behind approval', () => {
    expect(seed).toMatch(/trust_level: 'auto'/);
  });
});

describe('the vocabulary has ONE home, and it is not the database', () => {
  it('reads the generated artifact instead of carrying its own copy', () => {
    expect(handler).toMatch(/import \{ BLOCK_TYPES_SCHEMA, IMPORTABLE_BLOCK_TYPES \} from '\.\.\/block-schema\.ts'/);
  });

  it('hardcodes no block type of its own', () => {
    // A second list would drift within a week — the same mistake that gave the
    // contract token list two copies. Only the parser's own regex may name the
    // shape, never a specific type.
    const code = handler.split('\n').filter((l) => !l.trim().startsWith('*') && !l.trim().startsWith('//') && !l.trim().startsWith('/*')).join('\n');
    for (const t of ['two-column', 'testimonials', 'parallax-section', "'hero'"]) {
      expect(code).not.toContain(t);
    }
  });
});

describe('two levels, so the catalogue never floods a context', () => {
  it('no argument returns the catalogue without the field specs', () => {
    const cat = handler.slice(handler.indexOf('if (!requested)'), handler.indexOf('const match ='));
    expect(cat).toMatch(/type: e\.type, name: e\.name, description: e\.description/);
    expect(cat).not.toMatch(/data: e\.data/);
  });

  it('points the caller at the second level explicitly', () => {
    expect(handler).toMatch(/Call again with block_type=<type>/);
  });

  it('an unknown type answers with the valid ones — a self-correcting error', () => {
    expect(handler).toMatch(/error: `Unknown block type: \$\{requested\}`/);
    expect(handler).toMatch(/available_types: IMPORTABLE_BLOCK_TYPES/);
  });
});

describe('it teaches the error agents actually make', () => {
  it('warns that Tiptap fields are objects, never strings — in the response itself', () => {
    // The single most common agent failure on pages: rich text sent as a
    // string saves fine and renders nothing.
    expect(handler).toMatch(/must be objects \(\{"type":"doc",…\}\), never strings/);
  });

  it('and in the instructions', () => {
    expect(seed).toMatch(/never strings/);
    expect(seed).toMatch(/renders nothing/);
  });

  it('names the silent-failure mode: unknown keys are ignored', () => {
    expect(seed).toMatch(/the block ignores keys it does not know, silently/);
  });
});
