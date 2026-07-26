// ingest_inbound_email — internal skill handler.
//
// Reads the connected company mailbox and writes each message into
// outbound_communications with direction='inbound'. The existing
// trg_touch_email_thread trigger then binds it to a thread, and a reply lands
// on the SAME thread — and therefore the same customer — as the message it
// answers.
//
// This is the missing half of a shared inbox that was otherwise fully built.
//
// Why one company mailbox rather than per-user mailboxes: the point is that a
// customer's reply is visible on the customer. A reply into a salesperson's own
// Gmail is invisible to the CRM and to FlowPilot — per-user mailboxes defeat
// the goal they appear to serve. Per-user identity belongs in the FROM name
// (profiles.email_from_name), not in a separate inbox.
//
// Reads through composio-proxy, NOT through scan_gmail_inbox: that older
// handler wants its own OAuth in site_settings.gmail_integration, which the
// fleet does not have. Composio is what is actually connected.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { bareEmail, resolveInboundEntity } from '../email/resolve-entity.ts';

interface Ctx { supabaseUrl: string; serviceKey: string }

export async function executeIngestInboundEmail(
  supabase: SupabaseClient,
  args: Record<string, unknown>,
  ctx: Ctx,
): Promise<Record<string, unknown>> {
  const maxResults = Math.min(Number(args?.max_results) || 25, 100);
  // Default excludes our own sent mail — we already record outbound at send time.
  const query = typeof args?.query === 'string' && args.query ? args.query : '-in:sent';

  const res = await fetch(`${ctx.supabaseUrl}/functions/v1/composio-proxy`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${ctx.serviceKey}`,
      'apikey': ctx.serviceKey,
    },
    body: JSON.stringify({ action: 'gmail_read', params: { query, max_results: maxResults } }),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok || payload?.error) {
    return {
      success: false,
      error: payload?.error ?? `gmail_read failed (${res.status})`,
      hint: 'Check the Composio connection: composio-proxy action "diagnose" reports key validity and connected accounts.',
    };
  }

  const messages: any[] = payload?.result?.data?.messages ?? [];
  if (!messages.length) return { success: true, scanned: 0, ingested: 0, skipped_existing: 0, linked: 0 };

  let ingested = 0, skippedExisting = 0, linked = 0;
  const unlinkedSenders = new Set<string>();

  for (const m of messages) {
    const messageId: string | null = m?.messageId ?? null;
    if (!messageId) continue;

    // Idempotency is enforced by a unique index too; checking first keeps the
    // common re-scan cheap and the counts honest.
    const { data: seen } = await supabase
      .from('outbound_communications')
      .select('id')
      .eq('message_id_header', messageId)
      .maybeSingle();
    if (seen) { skippedExisting++; continue; }

    const sender = bareEmail(m?.sender);
    const subject: string | null = m?.subject ?? null;

    // Resolution lives in _shared/email/resolve-entity so the push path
    // (composio-webhook) and this poll path cannot answer differently for the
    // same message.
    const entity = await resolveInboundEntity(supabase, {
      sender: m?.sender ?? null,
      subject,
      threadId: m?.threadId ?? null,
    });
    const entityId = entity.related_entity_id;
    if (!entityId && sender) unlinkedSenders.add(sender);

    const { error } = await supabase.from('outbound_communications').insert({
      channel: 'email',
      direction: 'inbound',
      status: 'received',
      provider: 'composio',
      recipient: m?.to ?? null,
      sender: m?.sender ?? null,
      subject,
      body_text: m?.messageText ?? null,
      source: 'ingest_inbound_email',
      thread_id: m?.threadId ?? null,
      message_id_header: messageId,
      related_entity_type: entity.related_entity_type,
      related_entity_id: entityId,
      sent_at: m?.messageTimestamp ?? null,
      metadata: { label_ids: m?.labelIds ?? [], has_attachments: (m?.attachmentList ?? []).length > 0, resolved_by: entity.resolved_by },
    });

    // A concurrent run may have inserted the same message between our check and
    // this write; the unique index turns that into a duplicate error, which is
    // the index doing its job, not a failure worth reporting as one.
    if (error) {
      if (String(error.message ?? '').includes('duplicate key')) { skippedExisting++; continue; }
      return { success: false, error: error.message, ingested, skipped_existing: skippedExisting };
    }

    ingested++;
    if (entityId) linked++;
  }

  return {
    success: true,
    scanned: messages.length,
    ingested,
    skipped_existing: skippedExisting,
    linked,
    unlinked_senders: Array.from(unlinkedSenders).slice(0, 20),
    note: linked < ingested
      ? 'Some messages are not attached to a customer. They are stored and visible — link them by adding the sender as a lead or company contact, or by replying from FlowWink so a thread is established.'
      : undefined,
  };
}
