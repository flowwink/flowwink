// enrich_company — internal skill handler.
//
// Data-Only (No AI). Scrapes a company website (via the web-scrape kernel
// function so admin-configured provider priority is respected) and extracts
// metadata (title, description, phone) deterministically. AI-powered analysis
// is FlowPilot's job. OpenClaw alignment: "hand" not "brain".
//
// Moved from the standalone `enrich-company` edge function (edge-surface
// refactor B1a, wave 1). Response objects unchanged; the web-scrape call keeps
// its HTTP hop (web-scrape is a shared utility slated for _shared-lib
// extraction in a later tranche, not this one).

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type { HandlerCtx } from './qualify-lead.ts';


/**
 * Swedish organisationsnummer: NNNNNN-NNNN where the tenth digit is a Luhn
 * check digit over the first nine. Swedish sites routinely print it in the
 * footer — the enrichment scrape already holds it; it was just never read.
 */
function luhnValid(digits: string): boolean {
  let sum = 0;
  for (let i = 0; i < 10; i++) {
    let d = parseInt(digits[i], 10);
    if (i % 2 === 0) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
  }
  return sum % 10 === 0;
}

export function extractOrgNumber(text: string): string | null {
  const seen = new Map<string, number>();
  for (const m of text.matchAll(/\b(\d{6})\s*[-–]\s*(\d{4})\b/g)) {
    const digits = m[1] + m[2];
    // Group digit ≥ 2 separates orgnr from personnummer-formatted dates.
    if (parseInt(digits[2], 10) < 2) continue;
    if (!luhnValid(digits)) continue;
    const formatted = `${m[1]}-${m[2]}`;
    seen.set(formatted, (seen.get(formatted) ?? 0) + 1);
  }
  if (seen.size === 0) return null;
  // Most frequent candidate wins — a footer number repeats across the page.
  return [...seen.entries()].sort((a, b) => b[1] - a[1])[0][0];
}

export async function executeEnrichCompany(
  supabase: SupabaseClient,
  args: Record<string, unknown>,
  ctx: HandlerCtx,
): Promise<Record<string, unknown>> {
  try {
    const { domain, companyId } = args as { domain?: string; companyId?: string };

    // Resolve domain from companyId if needed
    let enrichDomain = domain;
    let targetCompanyId = companyId;
    let companyName: string | null = null;

    if (!enrichDomain && companyId) {
      const { data: company, error: companyError } = await supabase
        .from('companies')
        .select('id, name, domain, enriched_at')
        .eq('id', companyId)
        .single();

      if (companyError || !company) {
        return { error: 'Company not found' };
      }

      if (!company.domain) {
        return { error: 'Company has no domain to enrich' };
      }

      if (company.enriched_at) {
        return { success: true, message: 'Already enriched', skipped: true };
      }

      enrichDomain = company.domain;
      targetCompanyId = company.id;
      companyName = (company as { name?: string }).name ?? null;
    }

    if (!enrichDomain) {
      return { error: 'Domain or companyId is required' };
    }

    // Normalize domain to URL
    const url = enrichDomain.startsWith('http') ? enrichDomain : `https://${enrichDomain}`;
    console.log(`Scraping website via web-scrape (priority-aware): ${url}`);

    // Delegate to web-scrape edge function so admin-configured provider priority
    // (SearXNG / Firecrawl / Jina order) is respected automatically.
    const scrapeResponse = await fetch(`${ctx.supabaseUrl}/functions/v1/web-scrape`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ctx.serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ url, max_length: 8000 }),
    });

    if (!scrapeResponse.ok) {
      const errorText = await scrapeResponse.text();
      console.error('web-scrape error:', errorText);
      return { error: 'Failed to scrape website', details: errorText };
    }

    const scrapeData = await scrapeResponse.json();
    const pageContent: string = scrapeData.content || '';
    const metadata: Record<string, any> = scrapeData.metadata || {};
    console.log(`Scraped via provider: ${scrapeData.provider}`);

    // Extract data from metadata (deterministic — no AI)
    // Org number: read the page first (Swedish sites print it in the footer).
    // If absent, one search round — accept only a number that appears in at
    // least two independent snippets, so a lookalike from a directory listing
    // for some OTHER company doesn't get written into master data.
    let orgNumber = extractOrgNumber(pageContent);
    if (!orgNumber && companyName) {
      // Two attempts: the search provider chain is measurably flaky (about one
      // empty response in three), and an empty round must not read as "this
      // company has no registered number".
      for (let attempt = 0; attempt < 2 && !orgNumber; attempt++) {
        try {
          const sr = await fetch(`${ctx.supabaseUrl}/functions/v1/web-search`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${ctx.serviceKey}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ query: `${companyName} organisationsnummer`, limit: 5 }),
          });
          if (!sr.ok) continue;
          const sd = await sr.json();
          const counts = new Map<string, number>();
          for (const r of (sd.results ?? [])) {
            const hit = extractOrgNumber(`${r.title ?? ''} ${r.description ?? ''}`);
            if (hit) counts.set(hit, (counts.get(hit) ?? 0) + 1);
          }
          console.log(`org-number search attempt ${attempt + 1}: ${sd.results?.length ?? 0} results, candidates:`, [...counts.entries()]);
          const best = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
          if (best && best[1] >= 2) orgNumber = best[0];
        } catch (e) {
          console.warn('org-number search fallback failed:', e);
        }
      }
    }

    const enrichment = {
      website: url,
      description: metadata.description || metadata.ogDescription || null,
      phone: extractPhone(pageContent),
      org_number: orgNumber,
      address: null as string | null,
      raw_content: pageContent.substring(0, 5000), // For FlowPilot to analyze later
    };

    console.log('Enrichment result:', JSON.stringify({ ...enrichment, raw_content: `[${enrichment.raw_content?.length || 0} chars]` }));

    // Update company record
    if (targetCompanyId) {
      const { error: updateError } = await supabase
        .from('companies')
        .update({
          website: enrichment.website,
          notes: enrichment.description || undefined,
          phone: enrichment.phone || undefined,
          enriched_at: new Date().toISOString(),
        })
        .eq('id', targetCompanyId);

      // Master data is written conservatively: only when the column is empty.
      // Enrichment must never overwrite an operator-entered org number.
      if (enrichment.org_number) {
        await supabase
          .from('companies')
          .update({ org_number: enrichment.org_number })
          .eq('id', targetCompanyId)
          .is('org_number', null);
      }

      if (updateError) {
        console.error('Failed to update company:', updateError);
      } else {
        console.log(`Company ${targetCompanyId} enriched successfully`);
      }
    }

    return { success: true, data: enrichment, companyId: targetCompanyId };
  } catch (error) {
    console.error('Error in enrich-company:', error);
    return { error: error instanceof Error ? error.message : 'Unknown error' };
  }
}

/** Extract phone number from content using regex (deterministic) */
function extractPhone(content: string): string | null {
  // Swedish and international phone patterns
  const patterns = [
    /(?:tel|phone|telefon)[:\s]*([+\d\s()-]{8,20})/i,
    /(\+46[\s.-]?\d{1,3}[\s.-]?\d{3,4}[\s.-]?\d{2,4})/,
    /(0\d{1,3}[\s.-]?\d{3,4}[\s.-]?\d{2,4})/,
  ];
  for (const p of patterns) {
    const m = content.match(p);
    if (m) return m[1].trim();
  }
  return null;
}
