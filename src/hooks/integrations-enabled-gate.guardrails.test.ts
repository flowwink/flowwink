import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { OPT_IN_KEYS, CONFIG_BASED_KEYS, configHasCredential, resolveIntegrationStatus } from './useIntegrations';

/**
 * The admin card and the sender must agree on what "enabled" means.
 *
 * They did not. `email-send` gates SMTP and Composio on `enabled === true`,
 * while the UI called an integration active as soon as its secret existed —
 * `enabled` being undefined read as "not explicitly disabled". So filling in the
 * card turned the badge green over a transport that never sent a single message,
 * and mail silently kept going out via Resend.
 *
 * These tests read the sender's real source, so the gate cannot drift back.
 */

const emailSend = readFileSync(
  resolve(__dirname, '../../supabase/functions/email-send/index.ts'),
  'utf-8',
);

/** `const smtpEnabled = smtpCfg.enabled === true && ...` → ['smtp', '=== true'] */
function backendGates(): Map<string, string> {
  const gates = new Map<string, string>();
  const re = /const (\w+)Enabled = \1Cfg\.enabled (===\s*true|!==\s*false)/g;
  for (const m of emailSend.matchAll(re)) {
    gates.set(m[1], m[2].replace(/\s+/g, ' '));
  }
  return gates;
}

describe('integration enabled-gate parity', () => {
  it('finds the sender gates at all (the regex still matches the source)', () => {
    const gates = backendGates();
    expect([...gates.keys()].sort()).toEqual(['composio', 'resend', 'smtp']);
  });

  it('every opt-in gate in the sender is declared in OPT_IN_KEYS', () => {
    for (const [provider, gate] of backendGates()) {
      if (gate === '=== true') {
        expect(
          OPT_IN_KEYS as ReadonlyArray<string>,
          `email-send gates "${provider}" on enabled === true, so the UI must not ` +
            `report it active while enabled is undefined. Add it to OPT_IN_KEYS.`,
        ).toContain(provider);
      }
    }
  });

  it('nothing is declared opt-in that the sender treats as opt-out', () => {
    const gates = backendGates();
    for (const key of OPT_IN_KEYS) {
      const gate = gates.get(key as string);
      if (gate) {
        expect(
          gate,
          `OPT_IN_KEYS claims "${key}" needs an explicit true, but email-send ` +
            `gates it on ${gate}. The card would under-report it as disabled.`,
        ).toBe('=== true');
      }
    }
  });

  it('an opt-in integration with a credential is NOT active until switched on', () => {
    const withHost = { smtp: { config: { host: 'smtp.example.com' } } } as never;
    const before = resolveIntegrationStatus('smtp', {}, withHost);
    expect(before.hasKey).toBe(true);
    expect(before.isActive).toBe(false);
    expect(before.status).toBe('disabled');

    const on = { smtp: { enabled: true, config: { host: 'smtp.example.com' } } } as never;
    expect(resolveIntegrationStatus('smtp', {}, on).isActive).toBe(true);
  });

  it('an opt-out integration stays active when enabled is undefined', () => {
    expect(resolveIntegrationStatus('resend', { resend: true }, {}).isActive).toBe(true);
  });
});

describe('smtp credential model', () => {
  it('is config-based, because the sender treats the password as optional', () => {
    expect(CONFIG_BASED_KEYS as ReadonlyArray<string>).toContain('smtp');
    // A relay that accepts unauthenticated mail must not read as unconfigured.
    expect(emailSend).toMatch(/pass:\s*Deno\.env\.get\("SMTP_PASS"\)\s*\?\?\s*""/);
  });

  it('counts the host as the credential', () => {
    expect(configHasCredential('smtp', { host: 'smtp.example.com' })).toBe(true);
    expect(configHasCredential('smtp', { host: '' })).toBe(false);
    expect(configHasCredential('smtp', undefined)).toBe(false);
  });

  it('the sender actually reads host from config, so the card is not decorative', () => {
    // Host was env-only once, which made the card's most important field a no-op.
    expect(emailSend).toMatch(/Deno\.env\.get\("SMTP_HOST"\)\s*\|\|\s*smtpEmailCfg\.host/);
    expect(emailSend).not.toMatch(/host:\s*Deno\.env\.get\("SMTP_HOST"\)!/);
  });
});
