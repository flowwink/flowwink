import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';

interface SendLeadEmailInput {
  leadId?: string;
  /** Recipient address — required. */
  to: string;
  subject: string;
  body: string;
}

function toHtml(text: string): string {
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  return escaped
    .split(/\n{2,}/)
    .map((p) => `<p>${p.replace(/\n/g, '<br />')}</p>`)
    .join('\n');
}

/**
 * Sends a real email to a contact through the provider-agnostic `email-send`
 * rail. `expects_reply` makes the router prefer the company mailbox (Composio /
 * Gmail) over Resend, so the reply comes back into the system.
 *
 * `email-send` writes outbound_communications itself — we never log the
 * activity client-side, we only refresh the views.
 */
export function useSendLeadEmail() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async ({ leadId, to, subject, body }: SendLeadEmailInput) => {
      if (!to) throw new Error('This contact has no email address.');

      const { data, error } = await supabase.functions.invoke('email-send', {
        body: {
          to,
          subject,
          text: body,
          html: toHtml(body),
          expects_reply: true,
          source: 'lead-compose',
          ...(leadId
            ? { related_entity_type: 'lead', related_entity_id: leadId }
            : {}),
        },
      });

      if (error) throw error;
      if (data && data.success === false) {
        throw new Error(data.error || 'The email provider rejected the send.');
      }
      return data as { provider?: string; simulated?: boolean } | null;
    },
    onSuccess: (data, { leadId }) => {
      qc.invalidateQueries({ queryKey: ['lead-communications', leadId] });
      qc.invalidateQueries({ queryKey: ['unified-timeline'] });
      qc.invalidateQueries({ queryKey: ['lead-activities', leadId] });
      qc.invalidateQueries({ queryKey: ['outbound-communications'] });
      qc.invalidateQueries({ queryKey: ['customer-360'] });
      if (data?.simulated) {
        toast.warning('Simulated — no email provider is configured, nothing left the platform.');
      } else {
        toast.success(`Email sent${data?.provider ? ` via ${data.provider}` : ''}`);
      }
    },
    onError: (e: Error) => {
      logger.error('Send lead email error:', e);
      toast.error(e.message || 'Could not send the email');
    },
  });
}
