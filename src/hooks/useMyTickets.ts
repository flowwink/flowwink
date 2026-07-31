import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import type { Ticket, TicketComment } from '@/hooks/useTickets';

/**
 * Tickets the signed-in customer is allowed to see. Visibility is enforced by
 * RLS (own tickets + active company-contact scope) — this hook adds no filters
 * of its own so the portal always mirrors the access rules.
 */
export function useMyTickets() {
  return useQuery({
    queryKey: ['my-tickets'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('tickets')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as Ticket[];
    },
  });
}

/** Public (non-internal) replies on one ticket. */
export function useMyTicketComments(ticketId: string | null) {
  return useQuery({
    queryKey: ['my-ticket-comments', ticketId],
    enabled: !!ticketId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ticket_comments')
        .select('*')
        .eq('ticket_id', ticketId!)
        .eq('is_internal', false)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return (data ?? []) as unknown as TicketComment[];
    },
  });
}

export function useAddMyTicketReply() {
  const qc = useQueryClient();
  const { toast } = useToast();
  return useMutation({
    mutationFn: async ({ ticketId, content }: { ticketId: string; content: string }) => {
      const { data: { user } } = await supabase.auth.getUser();
      const { error } = await supabase.from('ticket_comments').insert([{
        ticket_id: ticketId,
        content,
        is_internal: false,
        author_type: 'customer',
        author_id: user?.id ?? null,
        author_name: user?.email ?? null,
      }] as never);
      if (error) throw error;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['my-ticket-comments', vars.ticketId] });
      toast({ title: 'Reply sent' });
    },
    onError: (err: Error) =>
      toast({ title: 'Could not send reply', description: err.message, variant: 'destructive' }),
  });
}
