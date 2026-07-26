import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Loader2, Link2 } from 'lucide-react';
import type { Comm } from './CommunicationDetailDialog';

/**
 * Attach an unlinked message to a contact. Binds the whole thread when the
 * message carries a thread id, so later replies inherit the customer.
 */
export function LinkCommunicationDialog({
  comm,
  onOpenChange,
}: {
  comm: Comm | null;
  onOpenChange: (open: boolean) => void;
}) {
  const [term, setTerm] = useState('');
  const qc = useQueryClient();

  const { data: leads = [], isFetching } = useQuery({
    queryKey: ['link-comm-lead-search', term],
    enabled: !!comm,
    queryFn: async () => {
      let q = supabase.from('leads').select('id, name, email').limit(10).order('created_at', { ascending: false });
      if (term.trim()) q = q.or(`name.ilike.%${term.trim()}%,email.ilike.%${term.trim()}%`);
      const { data, error } = await q;
      if (error) throw error;
      return data ?? [];
    },
  });

  const link = useMutation({
    mutationFn: async (leadId: string) => {
      if (!comm) return;
      const patch = { related_entity_type: 'lead', related_entity_id: leadId };

      // Whole thread inherits the binding when there is a thread id.
      const { error } = comm.thread_id
        ? await supabase.from('outbound_communications').update(patch).eq('thread_id', comm.thread_id)
        : await supabase.from('outbound_communications').update(patch).eq('id', comm.id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['outbound-communications'] });
      qc.invalidateQueries({ queryKey: ['comm-entity-names'] });
      qc.invalidateQueries({ queryKey: ['unified-timeline'] });
      toast.success('Message linked to contact');
      onOpenChange(false);
    },
    onError: (e: Error) => {
      logger.error('Link communication error:', e);
      toast.error(e.message || 'Could not link the message');
    },
  });

  return (
    <Dialog open={!!comm} onOpenChange={(v) => !v && onOpenChange(false)}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Link to a customer</DialogTitle>
          <DialogDescription>
            {comm?.thread_id
              ? 'The whole thread inherits this binding, so later replies land on the same contact.'
              : 'This message has no thread id — only this row is bound.'}
          </DialogDescription>
        </DialogHeader>

        <Input
          placeholder="Search contacts by name or email…"
          value={term}
          onChange={(e) => setTerm(e.target.value)}
        />

        <div className="max-h-72 overflow-y-auto divide-y divide-border rounded-md border border-border">
          {isFetching && <p className="p-3 text-sm text-muted-foreground">Searching…</p>}
          {!isFetching && leads.length === 0 && (
            <p className="p-3 text-sm text-muted-foreground">No contacts found.</p>
          )}
          {leads.map((l) => (
            <button
              key={l.id}
              type="button"
              disabled={link.isPending}
              onClick={() => link.mutate(l.id)}
              className="w-full text-left p-3 hover:bg-muted/60 transition-colors flex items-center gap-2"
            >
              <Link2 className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
              <span className="text-sm font-medium truncate">{l.name || l.email}</span>
              {l.name && <span className="text-xs text-muted-foreground truncate">{l.email}</span>}
              {link.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin ml-auto" />}
            </button>
          ))}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
