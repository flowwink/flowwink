# Composio Gmail sync — how FlowWink talks to Gmail

> Current state of the Gmail integration: what it does, what it does **not** do, and how to operate it.

FlowWink uses [Composio](https://composio.dev) as the OAuth + transport layer for Gmail. A single Gmail account is connected per FlowWink site (multi-account support is prepared in the schema but not exposed in the UI). The integration is **event-driven**, not a continuous two-way mailbox mirror.

---

## Mental model: event-driven mirror

```text
OUTBOUND (FlowWink → Gmail)
  User / skill calls email-send
  → composio-proxy (GMAIL_SEND_EMAIL)
  → Composio
  → Gmail
  → outbound_communications row written

INBOUND (Gmail → FlowWink)
  New mail arrives in Gmail inbox
  → Composio trigger (GMAIL_NEW_GMAIL_MESSAGE) notices it
  → Composio POSTs to composio-webhook
  → composio-webhook fetches the full message via composio-proxy
  → inbound row written to outbound_communications (direction = inbound)
  → platform event email.received emitted
  → event-dispatcher fans out to automations
```

**Key implication:** FlowWink does **not** poll the Gmail inbox. It only learns about mail when Composio tells it something changed. Historical mail in Gmail is never imported automatically.

---

## Components

| Component | File / location | Responsibility |
|-----------|-----------------|----------------|
| **Composio integration card** | `src/components/admin/modules/ComposioPanel.tsx` | Connect/disconnect Gmail, show connected identity, run diagnostics, copy the project-wide webhook URL. |
| **Email Router** | `src/components/admin/email/InboundMailboxesSection.tsx` | Register which inbound address FlowWink should listen to, choose routing mode, enable the trigger, activate Gmail Watch. |
| **composio-proxy** | `supabase/functions/composio-proxy/index.ts` | Authenticated proxy to Composio v3 API: send/read Gmail, manage triggers, diagnose connection. |
| **composio-webhook** | `supabase/functions/composio-webhook/index.ts` | Public receiver for Composio push events; expands message, resolves sender, logs inbound communication, emits `email.received`. |
| **resolve-entity** | `supabase/functions/_shared/email/resolve-entity.ts` | Matches an inbound sender to a contact, lead, or company so the reply lands on the right record. |

---

## Outbound flow

1. Caller invokes `email-send` edge function (or calls `composio-proxy` directly with `action: 'gmail_send'`).
2. `composio-proxy` resolves the active Gmail `connected_account_id`.
3. It executes `GMAIL_SEND_EMAIL` through Composio v3.
4. On success, a row is inserted into `outbound_communications` with:
   - `direction = 'outbound'`
   - `channel = 'email'`
   - `provider = 'composio'`
   - `status = 'sent'`
   - `recipient`, `subject`, `body_text`
   - `metadata.gmail_message_id`, `metadata.thread_id`

The `From` address is always the connected Gmail account. Per-user `From` / `Reply-To` is only supported by the Resend transport, not Gmail via Composio.

---

## Inbound flow

1. A new message lands in the connected Gmail inbox.
2. Composio's trigger instance (created by `enable_trigger`) detects it and POSTs to the project-wide webhook URL.
3. `composio-webhook` verifies the signature (if `COMPOSIO_WEBHOOK_SECRET` is set).
4. It extracts `message_id`, `thread_id`, and `connected_account_id` from the payload.
5. It looks up the matching `inbound_email_accounts` row.
6. It calls `composio-proxy` (`action: 'gmail_get'`) to fetch the full message.
7. It parses headers (`From`, `To`, `Subject`, `In-Reply-To`, `References`, `Message-Id`) and a plain-text body.
8. It calls `resolveInboundEntity()` to attach the mail to a contact / lead / company.
9. It inserts an `outbound_communications` row with `direction = 'inbound'`.
10. It emits `email.received` so automations can react.

---

## Routing modes

Set per mailbox in the Email Router:

| Mode | Behaviour |
|------|-----------|
| `crm_only` | Always attach to the matching contact/lead/company. Never create a ticket. |
| `crm_then_ticket` | Attach to CRM record if found; otherwise create a ticket. |
| `ticket_only` | Always create a ticket (requires the Tickets module). |

The default is `crm_only`.

### Classification (noise gate)

Every ingested message is classified in `_shared/email/ingest-gmail.ts` and the
result is stored on `outbound_communications.metadata.classification` and sent
with the `email.received` event:

| Value | Meaning |
|-------|---------|
| `known` | Resolved to a lead/contact/company in the CRM. |
| `noise` | Bulk/marketing/system mail — `List-Unsubscribe`, `List-Id`, `Precedence: bulk`, `Auto-Submitted`, `Feedback-ID`, or a `noreply@`/`notifications@`/`newsletter@`-style sender. |
| `unknown` | A human we don't have a record for yet. |

The event carries `should_create_ticket`, which is the combination of route mode
and classification. `internal:email_to_ticket` refuses to create a ticket when
the message is `noise` or `should_create_ticket` is false — pass `force: true`
to override for manual replay. This is what keeps newsletters out of the
helpdesk on a `crm_only` mailbox.


---

## Configuration checklist

1. **Set `COMPOSIO_API_KEY`** in Supabase secrets / Vault.
2. **(Optional) Set `COMPOSIO_WEBHOOK_SECRET`** for signature verification.
3. Open **Admin → Integrations → Composio**.
4. Click **Connect Gmail** and complete OAuth.
5. Copy the **Composio webhook URL** from the integration card and paste it into Composio dashboard → Project Settings → Webhooks.
6. Open **Admin → Communications → Settings** (Email Router).
7. Click **Register connected Gmail as company inbox**.
8. Click **Enable trigger** on the mailbox row.
9. Click **Activate watch** to enable Gmail Pub/Sub push (recommended; falls back to polling if not active).

---

## Latency expectations

| Path | Expected latency | Notes |
|------|------------------|-------|
| Outbound send | Seconds | Usually 1–5 s through Composio. |
| Inbound with Gmail Watch active | Seconds | Push from Gmail → Composio → FlowWink. |
| Inbound without Watch (polling) | Up to ~15 min | Composio polls; observed delays of ~1 hour have happened during trigger warm-up. |

If inbound mail is not arriving, check Composio dashboard first: the issue is almost always upstream of FlowWink.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| "Gmail not connected" | No active Composio connection | Re-run OAuth in Composio integration card. |
| Trigger enabled but no events | Webhook URL missing/wrong in Composio dashboard | Copy URL from integration card, paste into Composio webhooks. |
| Events arrive but no CRM link | `resolveInboundEntity` could not match sender | Add the contact/lead with this email, or manually link in Communications. |
| Inbound creates duplicate rows | `message_id_header` missing or changed | Check that Gmail returns a stable `Message-Id` header. |
| Outbound logged as failed | Composio error | Read `error_message` in `outbound_communications`; re-auth if token expired. |
| Composio diagnostic shows key invalid | Wrong `COMPOSIO_API_KEY` | Compare fingerprint in UI with dashboard. |

---

## Security

- `composio-proxy` requires a valid Supabase JWT (or service role).
- `composio-webhook` is public (`--no-verify-jwt`) because Composio calls it server-to-server.
- Webhook signatures are verified when `COMPOSIO_WEBHOOK_SECRET` is configured.
- The secret supports raw, hex, and base64 encodings, plus Standard Webhooks (`whsec_`) format.
- Outbound mail is logged before the send returns; inbound mail is deduplicated on `message_id_header`.

---

## Limitations

- **One primary company inbox** in the current UI. The `inbound_email_accounts` table already supports multiple rows; UI support is future work.
- **No historical import.** Only mail that arrives after the trigger is active is processed.
- **No Sent Items sync.** Outbound mail is logged from FlowWink's own send call, not read back from Gmail.
- **Polling fallback is slow.** For real-time inbound, Gmail Watch must be active.
- **Per-user From addresses** are not supported over Gmail/Composio; use Resend for that.

---

## Schema

```text
inbound_email_accounts
  id
  provider                -- 'composio_gmail'
  email_address           -- the mailbox address
  composio_account_id     -- Composio connected account id
  enabled
  is_shared
  route_mode              -- 'crm_only' | 'crm_then_ticket' | 'ticket_only'
  watch_expires_at
  last_received_at
  last_history_id
  created_at

outbound_communications
  id
  direction               -- 'outbound' | 'inbound'
  channel                 -- 'email'
  provider                -- 'composio'
  status
  sender
  recipient
  subject
  body_text
  message_id_header
  in_reply_to
  thread_id
  related_entity_type     -- 'contact' | 'lead' | 'company' | null
  related_entity_id
  metadata
  sent_at
```

---

## Reconcile fallback (polling)

Composio's push delivery is bursty — observed gaps from minutes up to 12 hours.
A polling fallback closes that window without changing the webhook path:

- **Shared ingest** — `supabase/functions/_shared/email/ingest-gmail.ts` holds the
  single ingest path (expand message → parse headers → resolve entity → log to
  `outbound_communications` → emit `email.received`). Both callers use it, so they
  cannot drift.
- **Webhook** — `composio-webhook` verifies the signature, then calls the shared ingest.
- **Poller** — `composio-proxy` action `gmail_reconcile` fetches recent inbox mail via
  `GMAIL_FETCH_EMAILS` and runs the same ingest per message.
- **Idempotency** — ingest dedupes on `metadata->>gmail_message_id` and on
  `message_id_header`, so re-running is a no-op.
- **Schedule** — pg_cron job `gmail-reconcile` runs `public.run_gmail_reconcile()`
  every 5 minutes. It no-ops when no enabled Composio mailbox exists, and calls
  `composio-proxy` with the anon key; that caller is restricted to `gmail_reconcile`
  and receives counts only.

No new edge function was added — reconcile reuses `composio-proxy`.

---

## Related docs

- [`docs/operators/system-settings.md`](../operators/system-settings.md) — integration secrets and environment variables.
- [`docs/operators/provisioning-and-updates.md`](../operators/provisioning-and-updates.md) — how to deploy edge functions.
- [`docs/architecture/edge-surface-classification.md`](../architecture/edge-surface-classification.md) — why `composio-proxy` and `composio-webhook` are separate functions.
