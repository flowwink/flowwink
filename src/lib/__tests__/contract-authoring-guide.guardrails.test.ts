import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The contract authoring guide — and the delivery path that makes it exist.
 *
 * The finding (Lovable's template test, 2026-08-08): an external MCP agent
 * produced technically valid but process-blind templates, because the gateway
 * delivered only description + schema. FlowPilot always had the lazy tier
 * (its built-in skill_read loads instructions before executing); external
 * agents had NO path to instructions at all. Two consumer types, ONE skill
 * contract, so both need the same two tiers:
 *
 *   choice tier  — description (+ has_instructions in the catalog)
 *   lazy tier    — instructions, via skill_read (FlowPilot) / read_skill (gateway)
 *
 * And the guide itself: FlowWink owns the FRAMEWORK (tokens, party block,
 * process couplings, per-type checklists); the INSTANCE owns the legal
 * content (the agent is told to read the instance's own templates/KB first).
 */

const gateway = readFileSync(
  resolve(__dirname, '../../../supabase/functions/mcp-server/index.ts'), 'utf-8');
const builtins = readFileSync(
  resolve(__dirname, '../../../supabase/functions/_shared/pilot/built-in-tools.ts'), 'utf-8');
const module_ = readFileSync(
  resolve(__dirname, '../../../src/lib/modules/contracts-module.ts'), 'utf-8');

const skillSeed = module_.slice(
  module_.indexOf("name: 'manage_contract_template'"),
  module_.indexOf("name: 'contract_renewal_check'"));

describe('both consumer types have the lazy tier', () => {
  it('FlowPilot: skill_read is a built-in that loads instructions before execution', () => {
    expect(builtins).toMatch(/name: 'skill_read'/);
  });

  it('external agents: the gateway registers read_skill as an MCP dispatch tool', () => {
    expect(gateway).toMatch(/server\.tool\("read_skill"/);
    // It returns the actual instructions, not just metadata.
    const tool = gateway.slice(gateway.indexOf('server.tool("read_skill"'));
    expect(tool.slice(0, 3000)).toMatch(/select\("name, description, instructions, tool_definition"\)/);
  });

  it('the REST mirror carries read_skill too — a dispatch tool on one transport only is the 2026-06-07 bug', () => {
    expect(gateway).toMatch(/dispatchMode && tool === "read_skill"/);
  });

  it('read_skill respects the same exposure gate as execute_skill (modules + groups)', () => {
    const mcpTool = gateway.slice(gateway.indexOf('server.tool("read_skill"'), gateway.indexOf('server.tool("execute_skill"'));
    expect(mcpTool).toMatch(/loadExposedSkills\(filterGroups\)/);
    const restBranch = gateway.slice(gateway.indexOf('dispatchMode && tool === "read_skill"'));
    expect(restBranch.slice(0, 1200)).toMatch(/loadExposedSkills\(effectiveGroups\(filterGroups, peerGroups\)\)/);
  });

  it('the choice tier reveals the lazy tier: search catalogs stamp has_instructions', () => {
    expect(gateway).toMatch(/annotateHasInstructions\(catalog\.skills\)/); // MCP
    expect(gateway).toMatch(/annotateHasInstructions\(catalog\)/); // REST
    expect(gateway).toMatch(/s\.has_instructions = withInstr\.has\(s\.name\)/);
  });

  it('missing instructions is a valid state, never an error (27% of skills)', () => {
    const tool = gateway.slice(gateway.indexOf('server.tool("read_skill"'));
    expect(tool.slice(0, 3500)).toMatch(/instructions: data\?\.instructions \?\? null/);
  });
});

describe('the guide: FlowWink owns the framework', () => {
  const instructions = skillSeed.slice(skillSeed.indexOf('instructions:'));

  it('opens with the ownership split and instance-context-first', () => {
    expect(instructions).toMatch(/FlowWink owns this framework; the INSTANCE owns the legal content/);
    expect(instructions).toMatch(/GATHER INSTANCE CONTEXT FIRST/);
    expect(instructions).toMatch(/list_contract_templates — the existing templates ARE the house style/);
    expect(instructions).toMatch(/search_kb \/ search_wiki/);
  });

  it('never lets the agent invent law or hardcode the supplier', () => {
    expect(instructions).toMatch(/Do not fabricate jurisdiction-specific legal text/);
    expect(instructions).toMatch(/NEVER hardcode it into a body/);
  });

  it('carries the FULL rendered token set — including the ones the old description omitted', () => {
    for (const t of ['{{supplier.name}}', '{{supplier.signatory}}', '{{counterparty.org_number}}',
                     '{{contract.number}}', '{{terms_url}}', '{{quote.lines}}']) {
      expect(instructions).toContain(t);
    }
  });

  it('prescribes the party block with merge tokens (the [BRACKETS]-party-block incident)', () => {
    expect(instructions).toMatch(/PARTY BLOCK/);
    expect(instructions).toMatch(/\{\{supplier\.name\}\}, org\.nr \{\{supplier\.org_number\}\}/);
  });

  it('couples the template to the processes: quote lines, billing, terms, obligations, signing, renewal', () => {
    expect(instructions).toMatch(/PROCESS COUPLINGS/);
    expect(instructions).toMatch(/references \{\{quote\.lines\}\}/);
    expect(instructions).toMatch(/the agreement IS the order; delivery is a status/);
    expect(instructions).toMatch(/CTR- invoice series/);
    expect(instructions).toMatch(/manage_contract_obligation can track each one/);
    expect(instructions).toMatch(/renewal_type\/renewal_notice_days METADATA/);
  });

  it('has a per-type checklist covering every contract_type the schema allows', () => {
    expect(instructions).toMatch(/PER-TYPE CHECKLIST/);
    for (const t of ['- service:', '- nda:', '- employment:', '- lease:', '- appendix (bilaga):']) {
      expect(instructions).toContain(t);
    }
  });

  it('appendices reference the PARENT number manually — the AliExpress rule holds', () => {
    expect(instructions).toMatch(/\[HUVUDAVTALETS NUMMER\] — the PARENT/);
  });
});

describe('the description (choice tier) stopped lying about the token set', () => {
  const description = skillSeed.slice(skillSeed.indexOf('description:'), skillSeed.indexOf('category:'));

  it('no longer claims the 8-token-only list — it points to the instructions', () => {
    // The old text said "ONLY these tokens are rendered" listing 8, while the
    // renderer handled 20 — description drift that steered agents away from
    // the party tokens.
    expect(description).not.toMatch(/ONLY these tokens are rendered/);
    expect(description).toMatch(/read_skill \/ skill_read/);
    expect(description).toMatch(/\{\{supplier\.\*\}\}/);
  });
});
