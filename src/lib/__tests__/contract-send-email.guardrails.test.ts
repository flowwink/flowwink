import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * "Send for signature" copied the link to the clipboard and emailed nothing —
 * a signing request could not leave the app. Quotes had an email path;
 * contracts did not. Magnus found it live: the resend button copied instead of
 * sent.
 */

const hook = readFileSync(
  resolve(__dirname, '../../hooks/useContractWorkflow.ts'), 'utf-8',
);
const handler = readFileSync(
  resolve(__dirname, '../../../supabase/functions/comms-send/contract_email.ts'), 'utf-8',
);
const dispatch = readFileSync(
  resolve(__dirname, '../../../supabase/functions/comms-send/index.ts'), 'utf-8',
);

describe('sending a contract actually emails the signing link', () => {
  it('useSendContract invokes comms-send with the contract_email kind', () => {
    expect(hook).toMatch(/invoke\('comms-send'/);
    expect(hook).toMatch(/kind:\s*'contract_email'/);
  });

  it('only falls back to clipboard when no mail went out', () => {
    // The old bug was clipboard-always. Now clipboard is the honest fallback.
    expect(hook).toMatch(/if \(emailed\)/);
    const success = hook.slice(hook.indexOf('onSuccess:'), hook.indexOf('onError:'));
    // the happy path reports a real send, not "link copied"
    expect(success).toMatch(/Signing link sent to/);
  });

  it('reports honestly when the provider only simulated', () => {
    expect(hook).toMatch(/No email provider configured/);
  });
});

describe('contract_email routes through the branded, provider-agnostic rail', () => {
  it('is a fragment sent via email-send, not a direct provider call', () => {
    const code = handler.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
    expect(code).toMatch(/invoke\('email-send'/);
    expect(code).not.toMatch(/<!doctype|<html[\s>]|<body[\s>]/i);
  });

  it('expects_reply — a signing request is a conversation', () => {
    expect(handler).toMatch(/expects_reply:\s*true/);
  });

  it('is registered in the comms-send dispatch', () => {
    expect(dispatch).toMatch(/contract_email:\s*contractEmail/);
  });
});

describe('the signing link and sender survive a wrong admin domain', () => {
  const handler = readFileSync(
    resolve(__dirname, '../../../supabase/functions/comms-send/contract_email.ts'), 'utf-8',
  ).split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');

  it('rebuilds the link from siteUrl + the contract token, not the passed URL', () => {
    // A salesperson on ot.garageai.eu must not mail an ot.garageai.eu link.
    expect(handler).toMatch(/siteUrl.*contract.*accept_token|\$\{siteUrl\}\/contract\/\$\{contract\.accept_token\}/s);
    expect(handler).toMatch(/g\.siteUrl/);
  });

  it('sends as the operator brand, not the generic FlowWink default', () => {
    // The subject read "from FlowWink" because general.site_name is empty on
    // most instances. Branding is the source of truth.
    expect(handler).toMatch(/b\.organizationName/);
  });
});
