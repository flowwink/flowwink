-- Internal ERP tables must not be writable by customer-portal users.
--
-- Security sweep 2026-07-13 found ~40 tables whose write policies were plain
-- `USING (true)` for the `authenticated` role. On a single-admin instance that
-- is inert. On an instance with a customer portal it is not: measured
-- 2026-07-25, www has 7 users — 1 admin and 5 CUSTOMERS — every one of whom
-- could in principle write vendors, purchase_orders, pos_sales, goods_receipts,
-- crm_tasks, document_share_links and the rest.
--
-- The original note called for introducing a staff role. That turned out to be
-- unnecessary: the app_role enum already carries employee, sales, hr,
-- accounting, support, warehouse, marketing, purchasing, projects, writer,
-- approver and admin. What was missing was a predicate that USES them.
--
-- is_staff() is deliberately shaped so it cannot break a working staff flow:
-- "holds at least one role that is not customer". Any of the twelve staff roles
-- passes, so no existing employee can lose access by having been given a role
-- this migration failed to enumerate. A customer-only user fails. A user with NO
-- role fails — which is the safe default for a half-provisioned account.
--
-- service_role bypasses RLS entirely, so edge functions and the agent layer are
-- unaffected by any of this.

CREATE OR REPLACE FUNCTION public.is_staff(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role <> 'customer'
  );
$$;

COMMENT ON FUNCTION public.is_staff(uuid) IS
  'True when the user holds at least one non-customer role. Use to gate internal '
  'ERP tables so customer-portal accounts cannot write them. Allow-shaped on '
  'purpose: any staff role passes, so adding a role never silently locks staff out.';

-- ─── Apply to internal ERP tables ───────────────────────────────────────────
--
-- The table list is the SECURITY DECISION and is explicit. Policy discovery is
-- dynamic because policy names have drifted slightly between instances, and a
-- migration that hardcoded them would silently skip the drifted ones — the
-- failure mode where a security fix reports success and changes nothing.
--
-- Deliberately NOT included, and why:
--   chat_feedback      — "Anyone can submit feedback" is the intended behaviour
--   audit_logs         — any authenticated actor must be able to append its own
--                        audit trail; gating it would create blind spots
--   agent_audit_trail  — written by the service role
--   beta_test_*        — the QA surface; findings/sessions are low-sensitivity
--                        and are how external testers report in
DO $$
DECLARE
  t text;
  p record;
  targets text[] := ARRAY[
    -- purchasing
    'vendors','purchase_orders','purchase_order_lines','purchase_order_revisions',
    'rfqs','rfq_bids','rfq_lines','goods_receipts','goods_receipt_lines',
    'vendor_credit_memos','vendor_invoice_disputes',
    -- point of sale
    'pos_sales','pos_sale_lines','pos_payments','pos_sessions',
    -- crm / sales
    'crm_tasks','deal_history','quote_revisions','quote_attachments',
    'recurring_quote_templates','subscription_plans',
    -- delivery
    'project_tasks','ticket_teams','ticket_team_members','ticket_escalation_rules',
    'ticket_time_entries','support_escalations',
    -- documents & content
    'contract_documents','contract_versions','document_share_links',
    'document_signature_requests','document_versions','content_proposals','wiki_pages'
  ];
BEGIN
  FOREACH t IN ARRAY targets LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'skipping %, not present on this instance', t;
      CONTINUE;
    END IF;

    FOR p IN
      SELECT policyname, cmd
        FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = t
         AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
         AND 'authenticated' = ANY(roles)
         -- Only the wide-open ones. A policy that already checks has_role, or
         -- scopes rows to their owner, is left exactly as it is.
         AND coalesce(qual, 'true') ~ '^(true)?$'
         AND coalesce(with_check, 'true') ~ '^(true)?$'
    LOOP
      -- INSERT has only WITH CHECK; DELETE has only USING; UPDATE/ALL have both.
      IF p.cmd = 'INSERT' THEN
        EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (public.is_staff(auth.uid()))',
                       p.policyname, t);
      ELSIF p.cmd = 'DELETE' THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (public.is_staff(auth.uid()))',
                       p.policyname, t);
      ELSE
        EXECUTE format('ALTER POLICY %I ON public.%I USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()))',
                       p.policyname, t);
      END IF;
      RAISE NOTICE 'gated %.% (%)', t, p.policyname, p.cmd;
    END LOOP;
  END LOOP;
END $$;
