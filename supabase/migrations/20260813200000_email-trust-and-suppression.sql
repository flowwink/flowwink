-- Email trust fields — what stands between "found an address" and "safe to
-- send to it".
--
-- Prospecting review (2026-08-13, against Apollo/Clay/Hunter practice):
-- Hunter's domain search already returns a confidence score, the address type
-- and its sources — prospect_research dropped all of it. These columns keep
-- it. Status starts 'unverified' and is upgraded by the explicit verify_email
-- skill (Hunter Email Verifier, costs a credit — deliberately a button, not a
-- sweep). Provenance doubles as the GDPR Art. 14 answer to "where did you get
-- my address".
--
-- The suppression side needed NO schema: email_suppressions, the email_events
-- ledger, the auto-suppress trigger (hard bounce / complaint / unsubscribed →
-- suppressed, lowercased) and email-send's skip-suppressed gate all shipped in
-- 20260708132027 and were verified live. What was missing was the WRITE path —
-- no mail carried an unsubscribe header and no endpoint existed to receive the
-- click. That lives in code: email-send now stamps RFC 8058 headers, and
-- email-webhook (public) gained the /unsubscribe route that records an
-- 'unsubscribed' event, which the existing trigger turns into a permanent
-- global suppression.

ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS email_confidence integer,
  ADD COLUMN IF NOT EXISTS email_status text DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS email_provenance jsonb;

COMMENT ON COLUMN public.leads.email_status IS
  'unverified | valid | invalid | accept_all | webmail | disposable | unknown — Hunter verifier vocabulary. Send gate: invalid/disposable block, accept_all/unknown warn.';
