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
  resolved_by: 'thread' | 'lead_email' | 'company_contact' | 'unresolved';
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

export async function resolveInboundEntity(
  supabase: Queryable,
  opts: { sender: string | null; subject: string | null; threadId: string | null },
): Promise<ResolvedEntity> {
  const sender = bareEmail(opts.sender);
  const primaryKey = threadKey(opts.subject, opts.threadId);
  const fallbackKey = subjectKey(opts.subject);

  const keysToTry = [primaryKey, fallbackKey].filter(
    (k, i, arr): k is string => !!k && arr.indexOf(k) === i,
  );

  for (const key of keysToTry) {
    const { data: thread } = await supabase
      .from('email_threads')
      .select('related_entity_type, related_entity_id')
      .eq('thread_key', key)
      .maybeSingle();
    if (thread?.related_entity_id) {
      return {
        related_entity_type: thread.related_entity_type,
        related_entity_id: thread.related_entity_id,
        resolved_by: 'thread',
      };
    }
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
