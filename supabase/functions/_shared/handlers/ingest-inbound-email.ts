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

interface Ctx { supabaseUrl: string; serviceKey: string }

/** `"liteit dev <liteitdev@gmail.com>"` → `liteitdev@gmail.com` */
function bareEmail(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const m = raw.match(/<([^>]+)>/);
  return (m ? m[1] : raw).trim().toLowerCase() || null;
}

/** Same normalisation the DB trigger uses, so we can look a thread up before insert. */
function threadKey(subject: string | null, threadId: string | null): string | null {
  const k = threadId || (subject ?? '').replace(/^(re:|fwd:|fw:)\s*/ig, '').toLowerCase();
  return k || null;
}

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
    const tKey = threadKey(subject, m?.threadId ?? null);

    // Entity resolution, strongest signal first.
    let entityType: string | null = null;
    let entityId: string | null = null;

    // 1. A reply to something we sent: inherit the thread's entity. This is the
    //    only signal that is certain, because WE set it when sending.
    if (tKey) {
      const { data: thread } = await supabase
        .from('email_threads')
        .select('related_entity_type, related_entity_id')
        .eq('thread_key', tKey)
        .maybeSingle();
      if (thread?.related_entity_id) {
        entityType = thread.related_entity_type;
        entityId = thread.related_entity_id;
      }
    }

    // 2. Otherwise match the sender address against known people.
    if (!entityId && sender) {
      const { data: lead } = await supabase
        .from('leads').select('id').ilike('email', sender).maybeSingle();
      if (lead) { entityType = 'lead'; entityId = lead.id; }
      else {
        const { data: contact } = await supabase
          .from('company_contacts').select('id').ilike('contact_email', sender).maybeSingle();
        if (contact) { entityType = 'company_contact'; entityId = contact.id; }
      }
    }

    // 3. No match: still ingest. An unattached message is visible and can be
    //    linked later; a dropped one is gone. Never guess an entity.
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
      related_entity_type: entityType,
      related_entity_id: entityId,
      sent_at: m?.messageTimestamp ?? null,
      metadata: { label_ids: m?.labelIds ?? [], has_attachments: (m?.attachmentList ?? []).length > 0 },
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
