import { describe, it, expect } from 'vitest';
import { normalizeSkillArgs } from '../../../supabase/functions/_shared/skill-aliases';

/**
 * `normalizeSkillArgs` runs on every skill call from every surface — the MCP
 * gateway, chat tool calls, FlowPilot's ReAct loop. Its monetary aliases
 * (amount→amount_cents, value→value_cents, …) rename the source key and delete
 * it, which is right for money and catastrophic for anything else that happens
 * to be called `value`.
 *
 * manage_site_settings takes exactly that: `{action:'update', key, value:{…}}`.
 * The settings object was being renamed to value_cents and dropped, so the
 * handler upserted the column default and answered `updated: true`. Nothing
 * failed anywhere — the write just quietly wrote `{}`. Found on optic when a
 * Swedish cookie banner stayed English after a "successful" update.
 */
describe('monetary aliases only rewrite money', () => {
  it('leaves an object `value` alone (manage_site_settings)', () => {
    const settings = { enabled: true, text: { title: 'Vi använder cookies' } };
    const out = normalizeSkillArgs({ action: 'update', key: 'cookie_consent_v2', value: settings });
    expect(out.value).toEqual(settings);
    expect(out.value_cents).toBeUndefined();
  });

  it('leaves arrays and booleans alone', () => {
    expect(normalizeSkillArgs({ value: [1, 2] }).value).toEqual([1, 2]);
    expect(normalizeSkillArgs({ value: false }).value).toBe(false);
    expect(normalizeSkillArgs({ total: { a: 1 } }).total).toEqual({ a: 1 });
  });

  it('still upscales whole-unit numbers to cents', () => {
    expect(normalizeSkillArgs({ amount: 100 }).amount_cents).toBe(10_000);
    expect(normalizeSkillArgs({ price: 49 }).price_cents).toBe(4_900);
    expect(normalizeSkillArgs({ amount: 100 }).amount).toBeUndefined();
  });

  it('still handles numeric strings', () => {
    expect(normalizeSkillArgs({ amount: '250.50' }).amount_cents).toBe('250.50');
    expect(normalizeSkillArgs({ amount: '250.50' }).amount).toBeUndefined();
  });

  it('never overwrites an explicit *_cents argument', () => {
    const out = normalizeSkillArgs({ amount: 100, amount_cents: 12_345 });
    expect(out.amount_cents).toBe(12_345);
  });

  it('keeps unwrapping data:{} — the other half of the contract', () => {
    const out = normalizeSkillArgs({ action: 'update', data: { key: 'branding', value: { logo: 'x' } } });
    expect(out.key).toBe('branding');
    expect(out.value).toEqual({ logo: 'x' });
  });
});
