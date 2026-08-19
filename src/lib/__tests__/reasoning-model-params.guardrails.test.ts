import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Reasoning-model param guardrail.
 *
 * gpt-5-class models 400 on /chat/completions when function tools are attached
 * without `reasoning_effort: 'none'`. The model name comes from the platform AI
 * map (site_settings.system_ai), so ANY call site that attaches tools to a
 * map-resolved model must handle the reasoning class via isOpenAiReasoningModel.
 *
 * This bit three surfaces in one day (2026-08-19): public chat, FlowWork
 * (workspace-chat), and reconciliation OCR. Each was a raw fetch that predated
 * the class. This test scans every edge-function file that both talks to the
 * OpenAI chat/completions endpoint and sends tools, and requires it to
 * reference reasoning_effort handling — so the next raw call site fails CI
 * instead of failing Svante.
 */

const FUNCTIONS_ROOT = join(__dirname, '../../../supabase/functions');

function walk(dir: string, acc: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, acc);
    else if (p.endsWith('.ts')) acc.push(p);
  }
  return acc;
}

describe('reasoning-model params (gpt-5-class + tools)', () => {
  it('every OpenAI chat/completions call site that sends tools handles reasoning_effort', () => {
    const offenders: string[] = [];
    for (const file of walk(FUNCTIONS_ROOT)) {
      const src = readFileSync(file, 'utf8');
      const talksToOpenAiChat =
        src.includes('api.openai.com/v1/chat/completions') ||
        (src.includes('chat/completions') && src.includes('OPENAI_API_KEY'));
      if (!talksToOpenAiChat) continue;
      const sendsTools = /\btools:\s/.test(src) || /\btool_choice\b/.test(src);
      if (!sendsTools) continue;
      const handlesReasoning =
        src.includes('reasoning_effort') || src.includes('isOpenAiReasoningModel');
      if (!handlesReasoning) offenders.push(file.replace(FUNCTIONS_ROOT, 'supabase/functions'));
    }
    expect(
      offenders,
      `These files attach tools to an OpenAI chat/completions call without handling ` +
        `reasoning-class models (gpt-5.x 400s without reasoning_effort:'none'). ` +
        `Use isOpenAiReasoningModel from _shared/ai-providers.ts.`,
    ).toEqual([]);
  });
});
