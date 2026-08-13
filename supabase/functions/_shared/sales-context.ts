/**
 * Sales Intelligence Context Loader
 *
 * Assembles a unified context string from:
 * 1. CMS Pages (CAG) — published products/services
 * 2. Site Settings — company_profile (unified source), company_name, brand_tone
 * 3. Sales Intelligence Profiles — user pitch (sender context)
 *
 * The Supabase client is INJECTED by the caller. This module used to create
 * its own service-role client via an https: esm.sh import, which forced the
 * fit-analysis handler into `await import(...)` for Node-test compatibility —
 * and the deployed edge runtime rejected that dynamic import at runtime, so
 * our_context silently became null in production: fit scores of 30 "because
 * the ICP is undefined" on instances whose ICP was sitting right there in
 * site_settings, and introduction letters written from zero context.
 */

export interface SalesContext {
  /** Formatted context string ready for AI prompts */
  formatted: string;
  /** Raw company profile data */
  companyProfile: Record<string, unknown>;
  /** Raw user profile data (if user_id provided) */
  userProfile: Record<string, unknown> | null;
  /** Site settings map */
  siteSettings: Record<string, unknown>;
  /** CMS page summaries */
  pagesSummary: string;
}

export async function loadSalesContext(supabase: any, options?: {
  userId?: string;
  includePages?: boolean;
  maxPageTokens?: number;
}): Promise<SalesContext> {
  const includePages = options?.includePages ?? true;
  const maxPageTokens = options?.maxPageTokens ?? 8000;

  // Parallel loads
  const [settingsRes, userProfileRes, pagesRes] = await Promise.all([
    // Layer 1: Site Settings (unified company profile source)
    supabase
      .from('site_settings')
      .select('key, value')
      .in('key', ['company_name', 'company_profile', 'brand_tone', 'industry']),

    // Layer 2: User profile from sales_intelligence_profiles (sender context only)
    options?.userId
      ? supabase
          .from('sales_intelligence_profiles')
          .select('data')
          .eq('type', 'user')
          .eq('user_id', options.userId)
          .maybeSingle()
      : Promise.resolve({ data: null }),

    // Layer 3: CMS Pages (published only)
    includePages
      ? supabase
          .from('pages')
          .select('title, slug, content_json, meta_json')
          .eq('status', 'published')
          .order('menu_order')
          .limit(30)
      : Promise.resolve({ data: [] }),
  ]);

  // --- Process site settings ---
  const settingsMap: Record<string, unknown> = {};
  for (const s of (settingsRes.data || [])) {
    settingsMap[s.key] = s.value;
  }

  // --- Company profile from unified site_settings source ---
  const companyProfile = (settingsMap.company_profile as Record<string, unknown>) || {};

  // --- User profile (sender context) ---
  const userProfile = (userProfileRes.data?.data as Record<string, unknown>) || null;

  // --- Process CMS pages into text summaries ---
  let pagesSummary = '';
  if (includePages && pagesRes.data && pagesRes.data.length > 0) {
    const pageTexts: string[] = [];
    let totalChars = 0;

    for (const page of pagesRes.data) {
      const blocks = page.content_json as any[];
      if (!blocks || !Array.isArray(blocks)) continue;

      const textParts: string[] = [];
      for (const block of blocks) {
        if (block.type === 'text' && block.data?.content) {
          const plain = (block.data.content as string).replace(/<[^>]*>/g, '').trim();
          if (plain) textParts.push(plain);
        } else if (block.type === 'hero' && block.data?.title) {
          textParts.push(block.data.title);
          if (block.data.subtitle) textParts.push(block.data.subtitle);
        } else if (block.type === 'features' && block.data?.features) {
          for (const f of block.data.features) {
            if (f.title) textParts.push(`${f.title}: ${f.description || ''}`);
          }
        }
      }

      if (textParts.length === 0) continue;

      const pageText = `### ${page.title}\n${textParts.join('\n')}`;
      totalChars += pageText.length;
      if (totalChars > maxPageTokens * 4) break;
      pageTexts.push(pageText);
    }

    pagesSummary = pageTexts.join('\n\n');
  }

  // --- Build formatted context ---
  const sections: string[] = [];

  // Company identity
  const companyName = (companyProfile.company_name as string) || (settingsMap.company_name as string) || '';
  if (companyName) {
    sections.push(`## Our Company: ${companyName}`);
  }

  // Company profile (from unified site_settings.company_profile)
  if (Object.keys(companyProfile).length > 0) {
    const cp = companyProfile;
    const profileParts: string[] = [];
    if (cp.about_us) profileParts.push(`About: ${cp.about_us}`);
    if (cp.value_proposition) profileParts.push(`Value Proposition: ${cp.value_proposition}`);
    if (cp.icp) profileParts.push(`Ideal Customer Profile: ${cp.icp}`);
    if (cp.differentiators) {
      const diffs = Array.isArray(cp.differentiators) ? cp.differentiators.join(', ') : cp.differentiators;
      profileParts.push(`Key Differentiators: ${diffs}`);
    }
    if (cp.competitors) profileParts.push(`Competitors: ${cp.competitors}`);
    if (cp.pricing_notes) profileParts.push(`Pricing: ${cp.pricing_notes}`);
    if (cp.industry) profileParts.push(`Industry: ${cp.industry}`);
    if (cp.services) {
      const svc = cp.services;
      // services moved from a Record to ServiceItem[] (normalizeServices in the
      // frontend migrates old data on read) — but this formatter only handled the
      // old object shape, so WHAT THE COMPANY SELLS silently vanished from the
      // fit-analysis context even though the readiness check lists it as required.
      if (Array.isArray(svc)) {
        const rows = (svc as Array<{ name?: string; description?: string } | string>)
          .map((it) => typeof it === 'string' ? it : `${it?.name ?? ''}${it?.description ? ` (${it.description})` : ''}`)
          .filter(Boolean);
        if (rows.length) profileParts.push(`Services: ${rows.join('; ')}`);
      } else if (typeof svc === 'object' && svc) {
        const svcParts = Object.entries(svc as Record<string, string>).map(([k, v]) => v ? `${k}: ${v}` : k);
        profileParts.push(`Services: ${svcParts.join('; ')}`);
      }
    }
    if (cp.clients) profileParts.push(`Notable Clients: ${cp.clients}`);
    if (cp.client_testimonials) profileParts.push(`Testimonials: ${cp.client_testimonials}`);
    if (cp.target_industries) {
      const inds = Array.isArray(cp.target_industries) ? cp.target_industries.join(', ') : cp.target_industries;
      profileParts.push(`Target Industries: ${inds}`);
    }
    if (cp.delivered_value) profileParts.push(`Delivered Value: ${cp.delivered_value}`);

    if (profileParts.length > 0) {
      sections.push(`## Company Profile\n${profileParts.join('\n')}`);
    }
  }

  // User profile (sender context)
  if (userProfile && Object.keys(userProfile).length > 0) {
    const up = userProfile;
    const userParts: string[] = [];
    if (up.full_name) userParts.push(`Name: ${up.full_name}`);
    if (up.title) userParts.push(`Title: ${up.title}`);
    if (up.email) userParts.push(`Email: ${up.email}`);
    if (up.personal_pitch) userParts.push(`Personal Pitch: ${up.personal_pitch}`);
    if (up.tone) userParts.push(`Preferred Tone: ${up.tone}`);
    if (up.signature) userParts.push(`Signature: ${up.signature}`);

    if (userParts.length > 0) {
      sections.push(`## Sender Profile\n${userParts.join('\n')}`);
    }
  }

  // CMS Pages
  if (pagesSummary) {
    sections.push(`## Our Products & Services (from website)\n${pagesSummary}`);
  }

  return {
    formatted: sections.join('\n\n'),
    companyProfile,
    userProfile,
    siteSettings: settingsMap,
    pagesSummary,
  };
}
