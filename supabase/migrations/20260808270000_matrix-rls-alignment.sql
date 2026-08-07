-- The module matrix grants a page; RLS decides whether it has rows.
--
-- A salesperson opened Newsletter — granted in role_module_access — and saw
-- zero subscribers. Not a permission error, not an empty list: RLS simply had
-- no read path for any role except admin. Empty pages are the worst failure
-- mode there is; nothing tells the user they lack access, so the system just
-- looks broken.
--
-- The sweep behind this migration found 78 tables readable only by admin.
-- Most are correctly admin-only (api_keys, audit_logs, agent internals). The
-- ones fixed here are those whose MODULE is granted to a non-admin role in
-- role_module_access — the exact set where the matrix promises a page the
-- database then empties. The biggest was not newsletter: `quotes` itself was
-- admin-only, so the entire quote flow was invisible to the sales role that
-- exists to run it.
--
-- Three tiers, because "staff" is not one audience:
--   1. Operational — any staff member may read (is_staff = any non-customer
--      role). The matrix stays the UI gate; RLS stops being a second,
--      contradictory gate.
--   2. HR-sensitive — admin + hr only. Salaries, disciplinary records and
--      candidate notes do not become readable just because someone is staff.
--   3. Finance-sensitive — admin + accounting only.
--
-- Writes are untouched: existing admin-manage policies still govern them.
-- This migration only opens READ paths that the matrix already promised.

-- ── 1. Operational: readable by any staff role ──────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- quotes module (sales, accounting) — the flow that started this
    'quotes',
    -- newsletter module (sales, support, marketing)
    'newsletters', 'newsletter_subscribers',
    'newsletter_email_opens', 'newsletter_link_clicks',
    -- forms module (sales, support, marketing): the replies ARE the module
    'form_submissions',
    -- ecommerce module (sales, warehouse)
    'discount_codes', 'back_in_stock_requests',
    -- knowledgeBase module (sales, support, marketing)
    'kb_article_revisions',
    -- leads module (sales)
    'lead_email_blasts', 'lead_email_blast_recipients',
    -- consultants module (sales)
    'consultant_checkin_log',
    -- companies/crm (sales) + outbound history staff need for context
    'contact_consents', 'outbound_communications'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Staff can read ' || t, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (is_staff(auth.uid()))',
        'Staff can read ' || t, t);
    END IF;
  END LOOP;
END $$;

-- ── 2. HR-sensitive: admin + hr ─────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- recruitment module (hr)
    'applications', 'application_stages', 'candidate_notes',
    -- hr module (hr)
    'disciplinary_actions', 'benefit_plans', 'salary_advances',
    'salary_grades', 'salary_structures', 'salary_structure_components'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'HR can read ' || t, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
        'USING (has_role(auth.uid(), ''admin''::app_role) OR has_role(auth.uid(), ''hr''::app_role))',
        'HR can read ' || t, t);
    END IF;
  END LOOP;
END $$;

-- ── 3. Finance-sensitive: admin + accounting ────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- accounting module
    'bank_accounts', 'bank_feed_connections', 'accounting_corrections',
    -- invoicing module
    'dunning_actions', 'dunning_sequences',
    -- subscriptions module
    'subscription_churn_reasons', 'subscription_winback_campaigns',
    'subscription_winback_sends',
    -- timesheets module
    'timesheet_period_locks'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Accounting can read ' || t, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
        'USING (has_role(auth.uid(), ''admin''::app_role) OR has_role(auth.uid(), ''accounting''::app_role))',
        'Accounting can read ' || t, t);
    END IF;
  END LOOP;
END $$;

-- Deliberately NOT touched, though the sweep flagged them: payroll_* (salary
-- amounts per person), auth_events, api_keys, audit_logs, agent internals,
-- webhook_logs, platform/demo/migration tables. Their modules are not granted
-- to a non-admin role in the matrix, so no page promises them — and payroll in
-- particular should stay admin-only until an explicit payroll role exists.
