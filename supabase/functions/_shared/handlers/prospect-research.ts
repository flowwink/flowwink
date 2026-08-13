// prospect_research — internal skill handler.
//
// Data Collector + CRM Persister. Chains: web-search → web-scrape →
// contact-finder. Persists the company + each Hunter contact (as a lead) so
// the rest of the Sales Intelligence flow (Fit Analysis, AI Compose, …) has
// DB IDs to operate on.
//
// Moved from the standalone `prospect-research` edge function (edge-surface
// refactor B1a, wave 1). One deliberate change: the contact-finder step is now
// a DIRECT LIBRARY CALL (executeContactFinder) instead of an internal HTTP hop
// — the first mesh-edge removed by the refactor. web-search/web-scrape keep
// their HTTP hops until the shared-utility tranche. Response objects unchanged.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { executeContactFinder } from './contact-finder.ts';
import type { HandlerCtx } from './qualify-lead.ts';
import { resolveAiConfig } from '../ai-config.ts';
import { callAiCompletion } from '../ai-usage-logger.ts';

interface CompanyDistillation {
  industry: string | null;
  size_estimate: string | null;
  main_offerings: string[];
  potential_pain_points: string[];
  summary: string | null;
}

/**
 * Distill what we read on their website into firmographics + pain points.
 * Soft-fail by design (Law 4): no AI provider or a bad response returns null
 * and research still succeeds with the raw scrape — the fit analysis then
 * grounds itself in web_summary instead of the distillation.
 */
async function distillCompany(
  supabase: SupabaseClient,
  companyName: string,
  websiteContent: string,
  searchSnippets: string,
): Promise<CompanyDistillation | null> {
  try {
    const ai = await resolveAiConfig(supabase, 'fast');
    const result = await callAiCompletion({
      supabase,
      source: 'prospect-research-distill',
      provider: ai.provider, model: ai.model, apiUrl: ai.apiUrl, apiKey: ai.apiKey,
      metadata: { company: companyName },
      body: {
        messages: [
          {
            role: 'system',
            content:
              'You distill raw website text about a company into firmographics for a CRM. ' +
              'Ground every field in the provided text only — never guess or embellish. ' +
              'Use null/empty when the text does not say.',
          },
          {
            role: 'user',
            content:
              `Company: ${companyName}\n\nWebsite content:\n${websiteContent.slice(0, 6000)}` +
              (searchSnippets ? `\n\nSearch snippets:\n${searchSnippets.slice(0, 1500)}` : ''),
          },
        ],
        tools: [{
          type: 'function',
          function: {
            name: 'save_company_profile',
            description: 'Save the distilled company profile',
            parameters: {
              type: 'object',
              properties: {
                industry: { type: ['string', 'null'], description: 'Primary industry, short (e.g. "Legal services / tax law")' },
                size_estimate: { type: ['string', 'null'], description: 'Size if stated or clearly inferable (e.g. "50-100 employees"), else null' },
                main_offerings: { type: 'array', items: { type: 'string' }, description: 'What they sell, max 6 short items' },
                potential_pain_points: { type: 'array', items: { type: 'string' }, description: 'Operational problems their kind of business plausibly has, max 5, grounded in what the site describes' },
                summary: { type: ['string', 'null'], description: '2-3 sentences: what this company does and for whom' },
              },
              required: ['industry', 'size_estimate', 'main_offerings', 'potential_pain_points', 'summary'],
            },
          },
        }],
        tool_choice: { type: 'function', function: { name: 'save_company_profile' } },
        temperature: 0.1,
      },
    });
    const toolCall = result?.choices?.[0]?.message?.tool_calls?.[0];
    const parsed = JSON.parse(toolCall?.function?.arguments ?? 'null');
    if (!parsed) return null;
    return {
      industry: parsed.industry ?? null,
      size_estimate: parsed.size_estimate ?? null,
      main_offerings: Array.isArray(parsed.main_offerings) ? parsed.main_offerings : [],
      potential_pain_points: Array.isArray(parsed.potential_pain_points) ? parsed.potential_pain_points : [],
      summary: parsed.summary ?? null,
    };
  } catch (e) {
    console.warn('[prospect-research] distillation skipped:', e instanceof Error ? e.message : e);
    return null;
  }
}

async function callEdge(ctx: HandlerCtx, functionName: string, body: Record<string, unknown>): Promise<any> {
  const res = await fetch(`${ctx.supabaseUrl}/functions/v1/${functionName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${ctx.serviceKey}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error(`${functionName} failed:`, text);
    return null;
  }
  return res.json();
}

export async function executeProspectResearch(
  supabase: SupabaseClient,
  args: Record<string, unknown>,
  ctx: HandlerCtx,
): Promise<Record<string, unknown>> {
  try {
    const { company_name, company_url } = args as { company_name?: string; company_url?: string };

    if (!company_name) {
      return { error: 'company_name is required' };
    }

    console.log(`Researching: ${company_name} (${company_url || 'no URL'})`);

    // Step 1: Web search
    const searchResult = await callEdge(ctx, 'web-search', {
      query: `${company_name} company about`,
      limit: 3,
    });

    // Step 2: Scrape company website
    let scrapeResult = null;
    const scrapeUrl = company_url || searchResult?.results?.[0]?.url;
    if (scrapeUrl) {
      scrapeResult = await callEdge(ctx, 'web-scrape', { url: scrapeUrl, max_length: 5000 });
    }

    // Step 3: Find contacts via Hunter.io (direct library call — no HTTP hop)
    let contactsRaw: any[] = [];
    let domain: string | null = null;
    if (scrapeUrl) {
      try {
        domain = new URL(scrapeUrl.startsWith('http') ? scrapeUrl : `https://${scrapeUrl}`).hostname.replace(/^www\./, '');
      } catch {
        domain = null;
      }
    }
    if (domain) {
      // Read admin-configured contact cap (defaults to 2 to save Hunter credits)
      // One domain search = ONE Hunter credit no matter how many contacts come
      // back — a low cap here throws away contacts already paid for. 10 is what
      // the search returns by default; the Email Finder (per person) is the
      // credit-expensive endpoint and is not used on this path.
      let maxContacts = 10;
      try {
        const { data: cfg } = await supabase
          .from('site_settings')
          .select('value')
          .eq('key', 'integrations')
          .maybeSingle();
        const n = (cfg?.value as any)?.hunter?.config?.maxContacts;
        if (typeof n === 'number' && n > 0) maxContacts = Math.min(n, 25);
      } catch (_) { /* fall through with default */ }

      const contactsRes = await executeContactFinder({
        action: 'domain_search',
        domain,
        limit: maxContacts,
      });
      contactsRaw = (contactsRes as any)?.contacts || [];
    }

    // Step 3.5: Distill what the website says into firmographics (soft-fail).
    // This is what fills industry/size — the exact fields every fit analysis
    // used to flag as missing while the answer sat unread in the scrape.
    const websiteContent: string = scrapeResult?.content || '';
    const searchSnippets = (searchResult?.results || [])
      .map((r: any) => r?.snippet || r?.description || '')
      .filter(Boolean)
      .join('\n');
    const distilled = websiteContent || searchSnippets
      ? await distillCompany(supabase, company_name, websiteContent, searchSnippets)
      : null;

    // Step 4: Persist company (upsert by name+domain)
    let companyId: string | null = null;
    {
      const { data: existing } = await supabase
        .from('companies')
        .select('id')
        .ilike('name', company_name)
        .maybeSingle();

      const companyPayload: Record<string, unknown> = {
        name: company_name,
        domain: domain ?? undefined,
        website: scrapeUrl ?? undefined,
        enriched_at: new Date().toISOString(),
        // Research keeps what it read: distillation first, raw excerpt as
        // fallback. The fit aggregator selects the row wholesale, so this is
        // how "what THEY do" reaches the scoring prompt.
        web_summary: distilled?.summary
          ? `${distilled.summary}\n\nOfferings: ${distilled.main_offerings.join('; ')}`
          : (websiteContent ? websiteContent.slice(0, 4000) : undefined),
        ...(distilled?.industry ? { industry: distilled.industry } : {}),
        ...(distilled?.size_estimate ? { size: distilled.size_estimate } : {}),
      };

      if (existing?.id) {
        await supabase.from('companies').update(companyPayload).eq('id', existing.id);
        companyId = existing.id;
      } else {
        const { data: inserted, error } = await supabase
          .from('companies')
          .insert(companyPayload)
          .select('id')
          .single();
        if (error) console.error('company insert failed:', error.message);
        companyId = inserted?.id ?? null;
      }
    }

    // Step 5: Persist contacts as leads (upsert by email)
    const savedContacts: Array<{
      id: string; email: string; name?: string;
      position?: string | null; seniority?: string | null;
      confidence?: number | null; type?: string | null;
    }> = [];
    for (const c of contactsRaw) {
      const email: string | undefined = c?.email || c?.value;
      if (!email) continue;
      const name = [c?.first_name, c?.last_name].filter(Boolean).join(' ').trim() || c?.name || undefined;

      const { data: existingLead } = await supabase
        .from('leads')
        .select('id')
        .ilike('email', email)
        .maybeSingle();

      const leadPayload: Record<string, unknown> = {
        email,
        name,
        company_id: companyId,
        source: 'prospect-research',
        status: 'lead',
        // Trust fields: what Hunter's domain search already told us, kept
        // instead of dropped. Status stays 'unverified' until an explicit
        // verify_email (that one costs a credit). Provenance doubles as the
        // GDPR Art. 14 answer to "where did you get my address".
        email_confidence: typeof c?.confidence === 'number' ? c.confidence : null,
        email_status: 'unverified',
        email_provenance: {
          provider: 'hunter',
          method: 'domain_search',
          type: c?.type ?? null,
          seniority: c?.seniority ?? null,
          // position/department: Hunter gives them, the seller needs them —
          // "Unknown role" next to a decision maker is a self-inflicted blank.
          position: c?.position ?? null,
          department: c?.department ?? null,
          sources_count: c?.sources_count ?? 0,
          found_at: new Date().toISOString(),
        },
      };

      const contactMeta = {
        position: c?.position ?? null,
        seniority: c?.seniority ?? null,
        confidence: typeof c?.confidence === 'number' ? c.confidence : null,
        type: c?.type ?? null,
      };

      if (existingLead?.id) {
        await supabase.from('leads').update({
          company_id: companyId,
          name,
          email_confidence: typeof c?.confidence === 'number' ? c.confidence : undefined,
          email_provenance: leadPayload.email_provenance,
        }).eq('id', existingLead.id);
        savedContacts.push({ id: existingLead.id, email, name, ...contactMeta });
      } else {
        const { data: inserted, error } = await supabase
          .from('leads')
          .insert(leadPayload)
          .select('id')
          .single();
        if (error) {
          console.error('lead insert failed:', error.message);
          continue;
        }
        if (inserted?.id) savedContacts.push({ id: inserted.id, email, name, ...contactMeta });
      }
    }

    // Step 6: Build UI-friendly payload (matches ResearchResult)
    const sources = {
      search: !!searchResult?.results?.length,
      scrape: !!scrapeResult?.content,
      contacts: savedContacts.length > 0,
    };
    // Every source silent means we researched nothing — the CRM row got created
    // either way, so an unqualified success:true reads as "researched, found
    // nothing about them" when the truth is "could not look". Say which.
    const researched = sources.search || sources.scrape || sources.contacts;

    const result = {
      success: true,
      researched,
      ...(researched ? {} : {
        warning:
          'No data source responded — this is not a finding about the company. ' +
          'Search, scrape and contact lookup all returned nothing, so nothing was ' +
          'enriched. Check that a search provider (SearXNG/Firecrawl) and ' +
          'HUNTER_API_KEY are configured before treating this as a dead prospect.',
      }),
      company: {
        id: companyId ?? undefined,
        name: company_name,
        domain: domain ?? undefined,
      },
      contacts: savedContacts,
      hunter_contacts_found: savedContacts.length,
      questions_and_answers: [],
      company_summary: {
        name: company_name,
        industry: distilled?.industry ?? undefined,
        size_estimate: distilled?.size_estimate ?? undefined,
        main_offerings: distilled?.main_offerings ?? [],
        potential_pain_points: distilled?.potential_pain_points ?? [],
      },
      // raw collected data preserved for FlowPilot
      _raw: {
        search_results: searchResult?.results || [],
        website_content: scrapeResult?.content?.substring(0, 3000) || null,
        website_metadata: scrapeResult?.metadata || null,
      },
      data_sources: sources,
    };

    console.log(
      `Research complete for ${company_name}: company=${!!companyId}, contacts_saved=${savedContacts.length}`,
    );

    return result;
  } catch (error) {
    console.error('Prospect research error:', error);
    return { error: error instanceof Error ? error.message : 'Unknown error' };
  }
}
