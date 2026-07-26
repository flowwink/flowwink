import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface EntityRef {
  label: string;
  href?: string;
}

type Pair = { type: string; id: string };

/**
 * Resolves the polymorphic `related_entity_type` / `related_entity_id` pairs on
 * communication rows to display names. One query per entity type — never per row.
 */
export function useCommEntityNames(pairs: Pair[]) {
  const key = Array.from(
    new Set(pairs.filter((p) => p.type && p.id).map((p) => `${p.type}:${p.id}`)),
  ).sort();

  return useQuery({
    queryKey: ['comm-entity-names', key],
    enabled: key.length > 0,
    staleTime: 60 * 1000,
    queryFn: async () => {
      const byType = new Map<string, string[]>();
      for (const k of key) {
        const [type, id] = k.split(':');
        byType.set(type, [...(byType.get(type) ?? []), id]);
      }

      const out: Record<string, EntityRef> = {};

      const jobs = Array.from(byType.entries()).map(async ([type, ids]) => {
        if (type === 'lead') {
          const { data } = await supabase.from('leads').select('id, name, email').in('id', ids);
          for (const r of data ?? []) {
            out[`lead:${r.id}`] = { label: r.name || r.email || 'Contact', href: `/admin/contacts/${r.id}` };
          }
        } else if (type === 'company_contact') {
          const { data } = await supabase
            .from('company_contacts')
            .select('id, contact_email, company_id, companies(name)')
            .in('id', ids);
          for (const r of data ?? []) {
            const company = (r as unknown as { companies?: { name?: string } }).companies?.name;
            out[`company_contact:${r.id}`] = {
              label: company ? `${r.contact_email} · ${company}` : r.contact_email,
              href: r.company_id ? `/admin/companies/${r.company_id}` : undefined,
            };
          }
        } else if (type === 'invoice') {
          const { data } = await supabase.from('invoices').select('id, invoice_number, customer_name').in('id', ids);
          for (const r of data ?? []) {
            out[`invoice:${r.id}`] = {
              label: `${r.invoice_number ?? 'Invoice'}${r.customer_name ? ` · ${r.customer_name}` : ''}`,
              href: `/admin/invoices`,
            };
          }
        } else if (type === 'lead_email_blast') {
          const { data } = await supabase.from('lead_email_blasts').select('id, subject').in('id', ids);
          for (const r of data ?? []) {
            out[`lead_email_blast:${r.id}`] = { label: r.subject || 'Email blast' };
          }
        }
      });

      await Promise.all(jobs);
      return out;
    },
  });
}
