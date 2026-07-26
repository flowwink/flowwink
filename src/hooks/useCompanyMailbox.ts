import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * The shared company mailbox — the address customer replies come back to.
 * Per-user mailboxes are deliberately out of scope: a reply into a personal
 * inbox is invisible to the CRM and to FlowPilot.
 */
export function useCompanyMailbox() {
  return useQuery({
    queryKey: ['company-mailbox'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('inbound_email_accounts')
        .select('email_address, enabled, provider')
        .eq('is_shared', true)
        .eq('enabled', true)
        .order('created_at', { ascending: true })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data ?? null;
    },
    staleTime: 5 * 60 * 1000,
  });
}
