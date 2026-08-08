DROP POLICY IF EXISTS "Service role can manage missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Service role can update missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Service role can read missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Admins manage federation_peer_missions" ON public.federation_peer_missions;
CREATE POLICY "Admins manage federation_peer_missions" ON public.federation_peer_missions
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Service inserts audit trail" ON public.agent_audit_trail;

DROP POLICY IF EXISTS "Allow anon insert on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated update on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated delete on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Admins manage beta_test_findings" ON public.beta_test_findings;
CREATE POLICY "Admins manage beta_test_findings" ON public.beta_test_findings
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Allow anon insert on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow anon update on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow authenticated update on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Admins manage beta_test_sessions" ON public.beta_test_sessions;
CREATE POLICY "Admins manage beta_test_sessions" ON public.beta_test_sessions
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Allow anon insert on beta_test_exchanges" ON public.beta_test_exchanges;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_exchanges" ON public.beta_test_exchanges;
DROP POLICY IF EXISTS "Admins manage beta_test_exchanges" ON public.beta_test_exchanges;
CREATE POLICY "Admins manage beta_test_exchanges" ON public.beta_test_exchanges
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "System can insert installed_template" ON public.installed_template;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'quotes',
    'newsletters', 'newsletter_subscribers',
    'newsletter_email_opens', 'newsletter_link_clicks',
    'form_submissions',
    'discount_codes', 'back_in_stock_requests',
    'kb_article_revisions',
    'lead_email_blasts', 'lead_email_blast_recipients',
    'consultant_checkin_log',
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

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'applications', 'application_stages', 'candidate_notes',
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

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'bank_accounts', 'bank_feed_connections', 'accounting_corrections',
    'dunning_actions', 'dunning_sequences',
    'subscription_churn_reasons', 'subscription_winback_campaigns',
    'subscription_winback_sends',
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

DO $$
DECLARE
  t text;
  operational text[] := ARRAY[
    'companies', 'deals', 'leads', 'deal_activities', 'lead_activities',
    'pipeline_stages',
    'quote_items', 'quote_signatures', 'quote_templates', 'quote_versions',
    'tickets', 'ticket_comments', 'sla_tiers', 'sla_tier_assignments',
    'sla_clock_pauses', 'service_credits', 'service_packages',
    'bookings', 'calendar_events', 'consultant_profiles',
    'consultant_assignments', 'consultant_skill_rates',
    'project_milestones', 'project_task_dependencies', 'project_templates',
    'products', 'gift_cards', 'loyalty_accounts', 'loyalty_transactions',
    'pos_tables', 'inventory_counts', 'inventory_count_lines',
    'stock_valuation_layers', 'landed_costs', 'shipping_pickups',
    'mo_work_orders', 'work_centers', 'routing_operations', 'equipment',
    'maintenance_requests', 'maintenance_schedules',
    'webinars', 'knowledge_chunks', 'cowork_messages',
    'subscriptions', 'subscription_events',
    'approval_chains', 'approval_steps', 'approval_groups',
    'approval_group_members', 'approval_delegations'
  ];
  hr_only text[] := ARRAY[
    'candidate_assessments', 'interviews', 'job_offers', 'reference_checks'
  ];
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