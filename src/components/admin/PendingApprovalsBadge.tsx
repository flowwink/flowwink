/**
 * PendingApprovalsBadge — count chip on the Approvals nav item.
 *
 * This IS the approver notification surface: the queue announces itself in
 * the navigation instead of posting into chat channels (the old
 * "Notify approvers in cowork chat" automation targeted cowork_messages,
 * which the Flowwork UI no longer renders). Realtime on INSERT/UPDATE with
 * a slow poll fallback; renders nothing when the queue is empty or the
 * table is unreachable.
 */
import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

const POLL_MS = 120_000;

export function usePendingApprovalCount() {
  // Visibility follows actionability (Svante-fynd 2026-08-18): the badge only
  // counts requests THIS user can resolve — admin sees all, others see those
  // whose required_role matches one of their roles. WHO approves what is
  // business config (approval rules set required_role per rule); the badge
  // just respects it instead of announcing a queue you cannot touch.
  const { isAdmin, roles } = useAuth();
  return useQuery({
    queryKey: ['approvals', 'pending-count', isAdmin, roles.join(',')],
    refetchInterval: POLL_MS,
    queryFn: async () => {
      let query = supabase
        .from('approval_requests')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'pending');
      if (!isAdmin) {
        if (roles.length === 0) return 0;
        query = query.in('required_role', roles);
      }
      const { count, error } = await query;
      if (error) return 0;
      return count ?? 0;
    },
  });
}

export function PendingApprovalsBadge() {
  const { data: count = 0 } = usePendingApprovalCount();
  const qc = useQueryClient();

  useEffect(() => {
    const channel = supabase
      .channel('approval_requests_badge')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'approval_requests' },
        () => void qc.invalidateQueries({ queryKey: ['approvals', 'pending-count'] }),
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [qc]);

  if (!count) return null;
  return (
    <span className="ml-auto inline-flex items-center justify-center rounded-full bg-primary text-primary-foreground text-[10px] font-medium h-4 min-w-4 px-1">
      {count > 99 ? '99+' : count}
    </span>
  );
}
