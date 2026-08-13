import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
/**
 * One lead's email deliverability status — the send gate's input.
 * Lives here (leads owns its table) so composers in other domains never read
 * the raw table; the table-ownership guardrail enforces exactly that.
 */
export function useLeadEmailStatus(leadId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['lead-email-status', leadId],
    enabled: enabled && !!leadId,
    queryFn: async (): Promise<string | null> => {
      const { data, error } = await supabase
        .from('leads')
        .select('email_status')
        .eq('id', leadId!)
        .maybeSingle();
      if (error) throw error;
      return (data as { email_status?: string } | null)?.email_status ?? null;
    },
  });
}
