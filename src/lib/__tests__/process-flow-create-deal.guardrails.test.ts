import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The contact view's process flow, step 2. Two findings (Magnus, 2026-08-08):
 *
 * 1. "Create opportunity" did nothing — it only scrolled to #lead-deals, which
 *    reads as a dead button when the section is already in view. A button that
 *    says create must CREATE.
 * 2. The step was labelled with the WRONG FUNNEL's word. There are two funnels
 *    by design: the contact funnel (status lead → opportunity → customer, a
 *    relationship ladder) and the deal pipeline (stages, the work). The step
 *    creates a DEAL; the contact status 'opportunity' is the CONSEQUENCE —
 *    auto-set when the first deal is created. One word per thing.
 */

const flow = readFileSync(
  resolve(__dirname, '../../../src/components/admin/crm/LeadProcessFlow.tsx'), 'utf-8');
const section = readFileSync(
  resolve(__dirname, '../../../src/components/admin/DealSection.tsx'), 'utf-8');
const dealsHook = readFileSync(
  resolve(__dirname, '../../../src/hooks/useDeals.ts'), 'utf-8');

describe('create means create', () => {
  it('the deal step dispatches the open-create-deal event, not just a scroll', () => {
    const dealCase = flow.slice(flow.indexOf("case 'deal':"), flow.indexOf("case 'quote':"));
    expect(dealCase).toMatch(/Create deal/);
    expect(dealCase).toMatch(/flowwink:open-create-deal/);
  });

  it('the deals section listens and opens its dialog', () => {
    expect(section).toMatch(/addEventListener\('flowwink:open-create-deal'/);
    expect(section).toMatch(/removeEventListener\('flowwink:open-create-deal'/);
  });
});

describe('the two funnels keep their own words', () => {
  it("the process step is labelled 'Deal' — the module's word, not the status word", () => {
    const dealStep = flow.slice(flow.indexOf("key: 'deal'"), flow.indexOf("key: 'quote'"));
    expect(dealStep).toMatch(/label: 'Deal'/);
    expect(dealStep).not.toMatch(/label: 'Opportunity'/);
  });

  it('the bridge exists: creating the first deal bumps the contact to opportunity', () => {
    // The contact-funnel status is a consequence of deal creation, not a step
    // the user performs. If this auto-bump ever disappears, the funnels drift.
    expect(dealsHook).toMatch(/updateLeadStatus\(data\.lead_id, 'opportunity', \{ onlyIfCurrentStatus: 'lead' \}\)/);
  });

  it('the help text teaches the bridge', () => {
    expect(flow).toMatch(/moves the contact to status Opportunity/);
  });
});
