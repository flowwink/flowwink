-- The role system moved on; RLS stayed behind.
--
-- A salesperson with the CRM modules granted saw zero leads, zero deals, zero
-- companies. Verified live under RLS, not inferred: 0 of 7 leads, 0 of 5
-- deals, 0 of 2 companies. The sales role exists to run that pipeline.
--
-- Root cause: 64 tables gate reads on `approver OR admin`. `approver` is
-- described in the codebase as "Legacy CMS role — treated as admin", it is
-- not in FUNCTIONAL_ROLES, role_module_access never grants it, and ZERO users
-- hold it. So those tables were admin-only in practice — while the module
-- matrix cheerfully granted their pages to eight functional roles. The matrix
-- promised a page; RLS delivered an empty one, with no error to explain it.
--
-- Fix: add an is_staff() READ path (any non-customer role) to the operational
-- tables, keeping admin-only for HR- and finance-sensitive ones. Writes are
-- untouched — the existing admin/approver policies still govern them. The
-- matrix stays the UI gate; RLS stops being a second, contradictory one.
--
-- The approver policies are LEFT IN PLACE. They cost nothing (nobody holds
-- the role) and removing 64 policies in the same migration that adds 64 is
-- two risks where one will do. Retiring the legacy role is its own task.
--
-- Method note, learned the hard way in this sweep: policy TEXT analysis
-- produced both false alarms (products and wiki_pages read fine) and misses
-- (the first pass skipped every policy containing "OR", hiding deals). Only
-- the live check under `SET LOCAL ROLE authenticated` + jwt claims told the
-- truth. Verify behaviour, not policy names or shapes.

DO $$
DECLARE
  t text;
  -- Operational: any staff member may READ. These back pages the matrix
  -- already grants to sales/support/marketing/warehouse/projects/purchasing.
  operational text[] := ARRAY[
    -- CRM core — the ones that started this
    'companies', 'deals', 'leads', 'deal_activities', 'lead_activities',
    'pipeline_stages',
    -- quotes & contracts flow
    'quote_items', 'quote_signatures', 'quote_templates', 'quote_versions',
    -- service delivery
    'tickets', 'ticket_comments', 'sla_tiers', 'sla_tier_assignments',
    'sla_clock_pauses', 'service_credits', 'service_packages',
    -- scheduling & consultants
    'bookings', 'calendar_events', 'consultant_profiles',
    'consultant_assignments', 'consultant_skill_rates',
    -- projects
    'project_milestones', 'project_task_dependencies', 'project_templates',
    -- commerce & inventory
    'products', 'gift_cards', 'loyalty_accounts', 'loyalty_transactions',
    'pos_tables', 'inventory_counts', 'inventory_count_lines',
    'stock_valuation_layers', 'landed_costs', 'shipping_pickups',
    -- manufacturing & field service
    'mo_work_orders', 'work_centers', 'routing_operations', 'equipment',
    'maintenance_requests', 'maintenance_schedules',
    -- marketing & knowledge
    'webinars', 'knowledge_chunks', 'cowork_messages',
    -- subscriptions (customer-facing side of the business)
    'subscriptions', 'subscription_events',
    -- approvals: staff must SEE what they are asked to approve
    'approval_chains', 'approval_steps', 'approval_groups',
    'approval_group_members', 'approval_delegations'
  ];
  -- HR-sensitive: admin + hr only. Assessments and offers do not become
  -- readable just because someone is staff.
  hr_only text[] := ARRAY[
    'candidate_assessments', 'interviews', 'job_offers', 'reference_checks'
  ];
  -- Finance-sensitive: admin + accounting only.
  finance_only text[] := ARRAY[
    'bank_transactions', 'bank_import_batches', 'budgets', 'petty_cash_counts',
    'expense_policies', 'vendor_invoices', 'reconciliation_matches',
    'reconciliation_rules', 'reconciliation_signoffs'
  ];
BEGIN
  FOREACH t IN ARRAY operational LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Staff can read ' || t, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (is_staff(auth.uid()))',
        'Staff can read ' || t, t);
    END IF;
  END LOOP;

  FOREACH t IN ARRAY hr_only LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'HR can read ' || t, t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
        'USING (has_role(auth.uid(), ''admin''::app_role) OR has_role(auth.uid(), ''hr''::app_role))',
        'HR can read ' || t, t);
    END IF;
  END LOOP;

  FOREACH t IN ARRAY finance_only LOOP
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
