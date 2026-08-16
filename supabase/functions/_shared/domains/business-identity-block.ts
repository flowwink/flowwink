// Business Identity as a prompt block — the grounding every outward-writing
// AI task should carry.
//
// Found while auditing campaign generation (2026-08-14): the content_proposal
// task asked the USER to retype brand voice, audience and industry per run
// while the answers sat in site_settings.company_profile — the exact page
// sales/marketing now curate. Same gap class as the fit analysis' missing
// our_context. This loader is deliberately in _shared/domains so every task
// that writes in the company's voice (content proposals, social batches, ad
// creative, …) grounds the same way — one identity, many mouths.
//
// Soft-fail: no profile → empty string, the task still runs on the brief.

export async function loadBusinessIdentityBlock(supabase: any): Promise<string> {
  try {
    const { data } = await supabase
      .from('site_settings')
      .select('key, value')
      .in('key', ['company_profile', 'brand_tone']);
    const map: Record<string, unknown> = {};
    for (const row of data ?? []) map[row.key] = row.value;
    const cp = (map.company_profile as Record<string, unknown>) ?? {};
    if (Object.keys(cp).length === 0 && !map.brand_tone) return '';

    const join = (v: unknown) => Array.isArray(v) ? v.map(String).join(', ') : typeof v === 'string' ? v : '';
    const lines: string[] = [];
    if (cp.company_name) lines.push(`Company: ${cp.company_name}`);
    if (cp.industry) lines.push(`Industry: ${cp.industry}`);
    if (cp.value_proposition) lines.push(`Value proposition: ${cp.value_proposition}`);
    if (cp.icp) lines.push(`Ideal customer profile: ${cp.icp}`);
    if (cp.differentiators) lines.push(`Differentiators: ${join(cp.differentiators)}`);
    if (Array.isArray(cp.services) && cp.services.length) {
      const svc = (cp.services as Array<{ name?: string } | string>)
        .map((s) => typeof s === 'string' ? s : s?.name ?? '').filter(Boolean).join('; ');
      if (svc) lines.push(`Services: ${svc}`);
    }
    if (cp.target_industries) lines.push(`Target industries: ${join(cp.target_industries)}`);
    if (map.brand_tone) lines.push(`Brand tone: ${typeof map.brand_tone === 'string' ? map.brand_tone : JSON.stringify(map.brand_tone)}`);
    if (lines.length === 0) return '';

    // claim_stance is a RULE about form, not a fact to recite — it governs how
    // every claim is phrased (e.g. "describe our services; never interpret
    // regulations on a customer's behalf; never imply buying us = compliance").
    // Appended after the facts so it reads as an instruction, and it must win
    // over the brief: a campaign brief cannot talk the model out of the stance.
    const stance = typeof cp.claim_stance === 'string' && cp.claim_stance.trim()
      ? `\nClaim stance (a rule about HOW claims are made — it overrides the brief): ${cp.claim_stance.trim()}`
      : '';

    return `\n\n## Company identity (Business Identity — ground everything in this)\n${lines.join('\n')}${stance}\nWrite as this company. Never contradict the identity; when the brief leaves voice, audience or industry unspecified, derive them from here.`;
  } catch {
    return '';
  }
}
