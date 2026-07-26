---
name: Auto-enable inbound mailbox when Composio Gmail becomes ACTIVE
description: Backlog — the UI has two "enabled" toggles (Composio account ACTIVE, inbound_email_accounts.enabled). Turning on Composio + connecting Gmail should be enough; the router row should default to enabled and the trigger auto-upserted.
type: feature
---

# Problem
Admin flow today requires saying "yes" three times:
1. Enable Composio module
2. Connect Gmail (OAuth) → account becomes ACTIVE
3. Go to Email Router → toggle `inbound_email_accounts.enabled = true`
4. Click "Enable trigger" (Composio `GMAIL_NEW_GMAIL_MESSAGE` upsert)
5. (Optional) Click "Activate watch" (Google Pub/Sub)

Steps 3–4 are the same intent as step 2 from the admin's mental model:
"I connected Gmail because I want inbound mail to flow into FlowWink."

## Fix
When a Composio Gmail account transitions to ACTIVE:
- Upsert `inbound_email_accounts` row with `enabled=true`, `route_mode='crm_then_ticket'` (default).
- Call `composio-proxy` `enable_trigger` for `GMAIL_NEW_GMAIL_MESSAGE` automatically.
- Surface the result in the connect-drawer ("Inbound routing: active") — no separate visit to Email Router required.

Email Router UI stays as the place to *change* routing policy (route_mode, disable, per-mailbox rules), not to activate it.

## Touchpoints
- `supabase/functions/composio-proxy/index.ts` (`connect_app` / OAuth callback path — detect ACTIVE and side-effect)
- OR `composio-webhook` when Composio sends `connected_account.updated → ACTIVE`
- `src/components/admin/integrations/ComposioAccountsList.tsx` — show "Inbound: active/paused" chip pulled from `inbound_email_accounts`
