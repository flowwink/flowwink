import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface PipelineChainStep {
  key: 'contact' | 'deal' | 'quote' | 'contract' | 'invoice';
  count: number;
  amountCents: number;
  done: boolean;
}

export interface LeadPipelineChain {
  deal: PipelineChainStep;
  quote: PipelineChainStep;
  contract: PipelineChainStep;
  invoice: PipelineChainStep;
}

/**
 * Reads the quote-to-cash chain for one contact in a single hook so the
 * lead page can show WHERE in the process the record stands.
 *
 * Linkage differs per object (that is the schema, not a choice here):
 * deals/quotes/invoices carry lead_id, contracts link by counterparty_email.
 */
export function useLeadPipelineChain(leadId: string | undefined, email: string | undefined) {
  return useQuery({
    queryKey: ['lead-pipeline-chain', leadId, email],
    queryFn: async (): Promise<LeadPipelineChain> => {
      const [deals, quotes, contracts, invoices] = await Promise.all([
        supabase.from('deals').select('id, value_cents, stage').eq('lead_id', leadId!),
        supabase.from('quotes').select('id, total_cents, status').eq('lead_id', leadId!),
        email
          ? supabase
              .from('contracts')
              .select('id, value_cents, status')
              .eq('counterparty_email', email)
          : Promise.resolve({ data: [], error: null } as never),
        supabase.from('invoices').select('id, total_cents, status').eq('lead_id', leadId!),
      ]);

      const sum = (rows: { value_cents?: number | null; total_cents?: number | null }[] | null) =>
        (rows ?? []).reduce((acc, r) => acc + (r.value_cents ?? r.total_cents ?? 0), 0);

      const step = (
        key: PipelineChainStep['key'],
        rows: { value_cents?: number | null; total_cents?: number | null }[] | null,
      ): PipelineChainStep => ({
        key,
        count: rows?.length ?? 0,
        amountCents: sum(rows),
        done: (rows?.length ?? 0) > 0,
      });

      return {
        deal: step('deal', deals.data as never),
        quote: step('quote', quotes.data as never),
        contract: step('contract', contracts.data as never),
        invoice: step('invoice', invoices.data as never),
      };
    },
    enabled: !!leadId,
    staleTime: 30 * 1000,
  });
}
