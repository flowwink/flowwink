// Resolve which record an inbound email belongs to.
//
// Shared deliberately: the push path (composio-webhook) and the poll path
// (ingest_inbound_email) must agree on who a message is from, or the same reply
// binds one way when it arrives by webhook and another way on a backfill. Two
// intakes with two answers is worse than one intake with none.
//
// The ordering is by CERTAINTY, not convenience:
//   1. The thread we started. We set related_entity_* when we sent, so
//      inheriting it is fact, not inference.
//   2. The sender address against people we know.
//   3. Nothing. An unattached message is visible and can be linked by hand; a
//      wrongly attached one is a lie in the customer's history that nobody
//      thinks to check. Never guess.
//
// Thread inheritance only works when outbound and inbound travel the same
// provider — Resend-sent plus Gmail-received share no thread id — so step 2 is
// the load-bearing one more often than it looks.

// Structurally typed rather than importing SupabaseClient, on purpose. Edge
// functions pin their own supabase-js versions (this webhook is on 2.45, the
// poll handler on 2.x latest) and the client's generics are not compatible
// across them — importing the type here would force every caller onto one
// version to satisfy a module that needs exactly one method.
type Queryable = { from: (table: string) => any };

export interface ResolvedEntity {
  related_entity_type: string | null;
  related_entity_id: string | null;
  /** Which rule matched — surfaced in logs and metadata so routing is auditable. */
  resolved_by:
    | 'thread'          // provider thread id — we set the binding when we sent
    | 'thread_subject'  // subject key, confirmed by the sender's address
    | 'lead_email'
    | 'company_contact'
    | 'unresolved';
}

const UNRESOLVED: ResolvedEntity = {
  related_entity_type: null,
  related_entity_id: null,
  resolved_by: 'unresolved',
};

/** `"Elin Marklund <elin@example.com>"` → `elin@example.com` */
export function bareEmail(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const m = raw.match(/<([^>]+)>/);
  return (m ? m[1] : raw).trim().toLowerCase() || null;
}

/**
 * Same normalisation trg_touch_email_thread applies, so a lookup here finds the
 * row the trigger created. Keep in step with that trigger.
 */
export function threadKey(subject: string | null, threadId: string | null): string | null {
  const k = threadId || (subject ?? '').replace(/^(re:|fwd:|fw:)\s*/ig, '').toLowerCase();
  return k || null;
}

/**
 * Normalised subject key, used as a fallback when threadId lookup misses.
 * Providers don't always round-trip thread ids (e.g. Composio's GMAIL_SEND_EMAIL
 * may not return the gmail threadId on send, so the outbound row is keyed by
 * subject; the inbound reply, however, carries a real gmail thread id). Trying
 * the subject key second lets us stitch those two halves back together without
 * guessing.
 */
export function subjectKey(subject: string | null): string | null {
  const k = (subject ?? '').replace(/^(re:|fwd:|fw:)\s*/ig, '').toLowerCase().trim();
  return k || null;
}

/**
 * Is this sender the person the thread belongs to?
 *
 * Only asked of the SUBJECT fallback, and the asymmetry is the point. A provider
 * thread id is unique and we wrote the binding ourselves, so a match there is
 * fact. A subject is neither unique nor ours: "Offert", "Faktura", "Hej" recur
 * across every customer a business has. Without this check, sending "Offert" to
 * one customer and receiving "Re: Offert" from an unrelated one files the second
 * into the first one's history — a falsehood nobody re-reads and notices.
 *
 * Unverifiable entity types (an invoice, a blast) answer false: better an
 * unattached message someone can link than a confident wrong one.
 */
async function senderBelongsToThread(
  supabase: Queryable,
  entityType: string | null,
  entityId: string,
  sender: string,
): Promise<boolean> {
  const lookup: Record<string, { table: string; column: string }> = {
    lead: { table: 'leads', column: 'email' },
    company_contact: { table: 'company_contacts', column: 'contact_email' },
  };
  const spec = lookup[entityType ?? ''];
  if (!spec) return false;

  const { data } = await supabase
    .from(spec.table)
    .select('id')
    .eq('id', entityId)
    .ilike(spec.column, sender)
    .maybeSingle();
  return !!data;
}

export async function resolveInboundEntity(
  supabase: Queryable,
  opts: { sender: string | null; subject: string | null; threadId: string | null },
): Promise<ResolvedEntity> {
  const sender = bareEmail(opts.sender);

  const findThread = async (key: string) => {
    const { data } = await supabase
      .from('email_threads')
      .select('related_entity_type, related_entity_id')
      .eq('thread_key', key)
      .maybeSingle();
    return data?.related_entity_id ? data : null;
  };

  // 1. The provider's own thread id. Unique, and WE wrote the binding when we
  //    sent — so a match is fact, and needs no corroboration.
  const providerThreadId = (opts.threadId ?? '').trim() || null;
  if (providerThreadId) {
    const thread = await findThread(providerThreadId);
    if (thread) {
      return {
        related_entity_type: thread.related_entity_type,
        related_entity_id: thread.related_entity_id,
        resolved_by: 'thread',
      };
    }
  }

  // 2. The subject key. Needed because Composio's send does not always return a
  //    gmail thread id, so our outbound row gets keyed by subject while the
  //    reply carries a real one — the two halves would never meet otherwise.
  //    But subjects are not unique and are not ours, so this match only counts
  //    when the sender is the person the thread belongs to.
  const subjKey = subjectKey(opts.subject);
  if (subjKey && subjKey !== providerThreadId) {
    const thread = await findThread(subjKey);
    if (thread && sender &&
        await senderBelongsToThread(supabase, thread.related_entity_type, thread.related_entity_id, sender)) {
      return {
        related_entity_type: thread.related_entity_type,
        related_entity_id: thread.related_entity_id,
        resolved_by: 'thread_subject',
      };
    }
    // A subject that matched but whose sender did not is deliberately NOT an
    // early return: fall through and let the address decide on its own merits.
  }

  if (!sender) return UNRESOLVED;

  const { data: lead } = await supabase
    .from('leads').select('id').ilike('email', sender).maybeSingle();
  if (lead) {
    return { related_entity_type: 'lead', related_entity_id: lead.id, resolved_by: 'lead_email' };
  }

  const { data: contact } = await supabase
    .from('company_contacts').select('id').ilike('contact_email', sender).maybeSingle();
  if (contact) {
    return {
      related_entity_type: 'company_contact',
      related_entity_id: contact.id,
      resolved_by: 'company_contact',
    };
  }

  return UNRESOLVED;
}
