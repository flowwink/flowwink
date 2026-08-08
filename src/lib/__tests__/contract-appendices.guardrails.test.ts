import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Appendices: what the agreement REFERENCES must be something it HOLDS — and
 * the counterparty must SEE it before signing.
 *
 * The gap was visible in production data: agent-authored agreements promising
 * "enligt Bilaga 1" with a precedence order, and nothing able to attach. An
 * appendix that the signing customer cannot see is not an appendix.
 */

const mig = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808400000_contract-appendices.sql'), 'utf-8');
const publicPage = readFileSync(
  resolve(__dirname, '../../../src/pages/PublicContractPage.tsx'), 'utf-8');
const panel = readFileSync(
  resolve(__dirname, '../../../src/components/admin/contracts/ContractAppendicesPanel.tsx'), 'utf-8');

describe('an appendix always contains something', () => {
  it('a file needs a URL and a document needs a body — no half-created appendices', () => {
    expect(mig).toMatch(/kind = 'file' AND file_url IS NOT NULL/);
    expect(mig).toMatch(/kind = 'document' AND coalesce\(trim\(body_markdown\), ''\) <> ''/);
  });

  it('relaxes the file columns so a markdown appendix can exist at all', () => {
    expect(mig).toMatch(/ALTER COLUMN file_name DROP NOT NULL/);
    expect(mig).toMatch(/ALTER COLUMN file_url  DROP NOT NULL/);
  });

  it('carries the label — the join between the prose and the object', () => {
    // The body says "Bilaga 1"; the register must carry that exact wording or
    // the customer cannot match the reference to the attachment.
    expect(mig).toMatch(/ADD COLUMN IF NOT EXISTS label text/);
    expect(mig).toMatch(/ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0/);
  });

  it('refuses to create an appendix with no content', () => {
    expect(mig).toMatch(/An appendix needs content: pass template, body_markdown or file_url/);
  });
});

describe('the counterparty sees them where they sign', () => {
  it('the public token RPC returns the appendices, ordered', () => {
    const fn = mig.slice(mig.indexOf('CREATE FUNCTION public.get_public_contract'));
    expect(fn).toMatch(/appendices jsonb/);
    expect(fn).toMatch(/ORDER BY d\.sort_order/);
    // Never NULL — the page must be able to read .length without a guard.
    expect(fn).toMatch(/coalesce\(\([\s\S]*?\), '\[\]'::jsonb\) AS appendices/);
  });

  it('the return type change drops the old function first (42P13 trap)', () => {
    const dropAt = mig.indexOf('DROP FUNCTION IF EXISTS public.get_public_contract(text)');
    const createAt = mig.indexOf('CREATE FUNCTION public.get_public_contract(p_token text)');
    expect(dropAt).toBeGreaterThan(-1);
    expect(dropAt).toBeLessThan(createAt);
  });

  it('the signing page renders document appendices INLINE, so the saved PDF is complete', () => {
    // Files can be links; a document appendix must be in the page itself or
    // "Save as PDF" produces an incomplete copy of what was signed.
    expect(publicPage).toMatch(/appendices[\s\S]{0,400}filter\(\(a\) => a\.kind === 'document' && a\.body_markdown\)/);
    expect(publicPage).toMatch(/<ReactMarkdown remarkPlugins=\{\[remarkGfm\]\}>\{a\.body_markdown as string\}/);
  });

  it('lists every appendix in one list, whatever its kind', () => {
    expect(publicPage).toMatch(/omfattas av din signering/);
    expect(publicPage).toMatch(/appendices\.map\(\(a\) =>/);
  });

  it('the open-file link never leaks the referrer', () => {
    expect(publicPage).toMatch(/rel="noreferrer noopener"/);
  });
});

describe('writes are staff-only', () => {
  it('drops the any-authenticated-user write policies', () => {
    expect(mig).toMatch(/DROP POLICY IF EXISTS "Authenticated users can create contract documents"/);
    expect(mig).toMatch(/DROP POLICY IF EXISTS "Authenticated users can delete contract documents"/);
  });

  it('the RPC gates on staff or service_role', () => {
    expect(mig).toMatch(/auth\.role\(\) = 'service_role' OR is_staff\(auth\.uid\(\)\)/);
    expect(mig).toMatch(/Only staff can manage contract appendices/);
  });
});

describe('appendices are not the same thing as documents', () => {
  it('the admin panel says what makes an appendix different', () => {
    // Documents (correspondence, the countersigned PDF) stay in the Documents
    // tab; only appendices travel to the counterparty as part of the signature.
    expect(panel).toMatch(/covered by the signature/);
    expect(panel).toMatch(/Documents tab/);
  });

  it('warns when the body references a Bilaga that does not exist', () => {
    expect(panel).toMatch(/signs a reference to something that isn/);
  });
});
