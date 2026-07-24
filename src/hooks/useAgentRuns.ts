import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Count of paused agent runs — surfaces in the sidebar so operators
 * see when FlowPilot needs human input.
 */
export function usePausedAgentRunCount() {
  return useQuery({
    queryKey: ['agent-runs', 'paused-count'],
    queryFn: async () => {
      const { count, error } = await supabase
        .from('agent_runs')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'paused');
      if (error) throw error;
      return count ?? 0;
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  });
}
