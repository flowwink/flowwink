/**
 * verify_email — explicit deliverability check via Hunter's Email Verifier.
 *
 * Deliberately a separate, on-demand step rather than an automatic sweep:
 * every verification costs one Hunter credit (50/month on the free plan), and
 * the 2026 practice the prospecting research settled on is find → verify →
 * gate, with verification spent only on addresses you actually intend to
 * contact. Discovery (domain search) already stamped confidence + provenance
 * for free; this upgrades email_status from 'unverified' to Hunter's verdict:
 *
 *   valid       → send
 *   accept_all  → catch-all domain: the server accepts everything, so this is
 *                 NOT a green light — ~30% bounce risk unverified. Warn.
 *   webmail     → personal mailbox (gmail etc.) — legitimate but low B2B trust
 *   disposable  → never send
 *   invalid     → never send
 *   unknown     → could not determine — treat as not sendable
 *
 * With lead_id, the verdict is written onto the lead so the send gate and the
 * timeline see it. Without, it is a pure lookup.
 */

interface VerifyEmailInput {
  email: string;
  lead_id?: string;
}

export async function executeVerifyEmail(
  supabase: any,
  args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const input = args as unknown as VerifyEmailInput;
  if (!input.email || typeof input.email !== 'string') {
    return { success: false, error: 'email is required' };
  }

  const hunterKey = Deno.env.get('HUNTER_API_KEY');
  if (!hunterKey) {
    return { success: false, error: 'HUNTER_API_KEY not configured. Add it in Settings → Secrets.' };
  }

  const params = new URLSearchParams({ email: input.email.trim(), api_key: hunterKey });
  const res = await fetch(`https://api.hunter.io/v2/email-verifier?${params}`);
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    return { success: false, error: `Hunter verifier error ${res.status}: ${body.slice(0, 200)}` };
  }

  const data = await res.json();
  const d = data?.data ?? {};
  const status: string = d.status ?? 'unknown';
  const score: number | null = typeof d.score === 'number' ? d.score : null;

  if (input.lead_id) {
    const { error } = await supabase
      .from('leads')
      .update({
        email_status: status,
        ...(score !== null ? { email_confidence: score } : {}),
      })
      .eq('id', input.lead_id);
    if (error) {
      return { success: true, status, score, lead_updated: false, warning: `Verified but lead update failed: ${error.message}` };
    }
  }

  return {
    success: true,
    email: input.email,
    status,
    score,
    // Send-gate summary the caller can act on without knowing the vocabulary.
    sendable: status === 'valid',
    caution: status === 'accept_all' || status === 'unknown' || status === 'webmail',
    lead_updated: !!input.lead_id,
  };
}
