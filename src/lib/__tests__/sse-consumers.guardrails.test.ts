import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

/**
 * chat-completion answers with Server-Sent Events. A caller that does
 * `await res.json()` on that stream gets
 *   Unexpected token 'd', "data: {"id"...
 * which is what a visitor saw when they pressed "Ask the assistant" in the FAQ
 * block — a dead button on a live site, and the kind of failure that only shows
 * up when someone actually clicks.
 *
 * Every caller of that endpoint must read the stream. This walks the callers
 * rather than listing them, so a new one cannot quietly repeat the mistake.
 */

const root = resolve(__dirname, '../..');

function walk(dir: string, out: string[] = []): string[] {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(p)) out.push(p);
  }
  return out;
}

const callers = walk(root)
  .map((p) => ({ path: p, src: readFileSync(p, 'utf-8') }))
  .filter(({ src }) => src.includes('functions/v1/chat-completion'));

describe('every chat-completion caller reads the stream', () => {
  it('finds the callers', () => {
    expect(callers.length).toBeGreaterThan(0);
  });

  for (const { path, src } of callers) {
    const name = path.replace(root + '/', '');
    it(`${name} does not parse the SSE stream as JSON`, () => {
      // A caller either reads the stream, or hands the response to something
      // that does. What it must never do is call .json() on it directly.
      const readsStream = src.includes('getReader');
      const parsesJson = /await\s+res(ponse)?\.json\(\)/.test(src);
      expect(
        parsesJson && !readsStream,
        `${name} calls .json() on a streaming endpoint — the visitor sees ` +
          `"Unexpected token 'd', \\"data: {...\\"" instead of an answer`,
      ).toBe(false);
    });
  }
});
