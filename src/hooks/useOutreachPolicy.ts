import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type OutreachPolicy = 'permissive' | 'consent_required' | 'unknown';

export interface OutreachPolicyResult {
  country: string | null;
  countryName: string | null;
  policy: OutreachPolicy;
  note: string | null;
}

/**
 * Which cold-outreach regime applies to THIS recipient — decided by the
 * recipient's country, never the sender's (ePrivacy is implemented per member
 * state, and the recipient's law governs).
 *
 * Owning-domain hook: the send dialog must not read `companies` raw. The
 * country comes from the lead's company; no company or no country means
 * 'unknown', which the UI shows as "check before sending" rather than silently
 * assuming the permissive case.
 */
export function useOutreachPolicy(leadId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['outreach-policy', leadId],
    enabled: enabled && !!leadId,
    queryFn: async (): Promise<OutreachPolicyResult> => {
      const { data: lead } = await supabase
        .from('leads')
        .select('company_id')
        .eq('id', leadId!)
        .maybeSingle();

      const companyId = (lead as { company_id?: string } | null)?.company_id;
      if (!companyId) return { country: null, countryName: null, policy: 'unknown', note: null };

      const { data: company } = await supabase
        .from('companies')
        .select('country')
        .eq('id', companyId)
        .maybeSingle();

      const country = (company as { country?: string } | null)?.country?.trim().toUpperCase() ?? null;
      if (!country) return { country: null, countryName: null, policy: 'unknown', note: null };

      const { data: row } = await supabase
        .from('outreach_country_policy' as never)
        .select('country_name, policy, note')
        .eq('country_code', country)
        .maybeSingle();

      const r = row as { country_name?: string; policy?: OutreachPolicy; note?: string } | null;
      return {
        country,
        countryName: r?.country_name ?? null,
        // A country we have no row for is UNKNOWN, never assumed permissive.
        policy: r?.policy ?? 'unknown',
        note: r?.note ?? null,
      };
    },
  });
}
