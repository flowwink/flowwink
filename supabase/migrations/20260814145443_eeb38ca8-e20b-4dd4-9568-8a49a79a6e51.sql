-- === 20260813140000_rls-reads-the-matrix.sql ===
CREATE OR REPLACE FUNCTION public.can_access_module(_user_id uuid, _module_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.has_role(_user_id, 'admin'::app_role)
      OR EXISTS (
           SELECT 1
             FROM public.user_roles ur
             JOIN public.role_module_access rma ON rma.role = ur.role
            WHERE ur.user_id = _user_id
              AND rma.module_id = _module_id
         );
$$;

GRANT EXECUTE ON FUNCTION public.can_access_module(uuid, text) TO authenticated, anon, service_role;

DO $$
DECLARE
  MAP CONSTANT text[][] := ARRAY[
    ARRAY['approval_chains', 'approvals'],
    ARRAY['approval_delegations', 'approvals'],
    ARRAY['approval_group_members', 'approvals'],
    ARRAY['approval_groups', 'approvals'],
    ARRAY['approval_steps', 'approvals'],
    ARRAY['back_in_stock_requests', 'ecommerce'],
    ARRAY['bookings', 'bookings'],
    ARRAY['calendar_events', 'calendar'],
    ARRAY['companies', 'companies'],
    ARRAY['consultant_assignments', 'consultants'],
    ARRAY['consultant_checkin_log', 'consultants'],
    ARRAY['consultant_profiles', 'consultants'],
    ARRAY['consultant_skill_rates', 'consultants'],
    ARRAY['contact_consents', 'leads'],
    ARRAY['content_proposals', 'paidGrowth'],
    ARRAY['contract_documents', 'contracts'],
    ARRAY['contract_versions', 'contracts'],
    ARRAY['cowork_messages', 'workspaceChat'],
    ARRAY['crm_tasks', 'leads'],
    ARRAY['deal_activities', 'deals'],
    ARRAY['deal_history', 'deals'],
    ARRAY['deals', 'deals'],
    ARRAY['discount_codes', 'ecommerce'],
    ARRAY['document_share_links', 'documents'],
    ARRAY['document_signature_requests', 'documents'],
    ARRAY['document_versions', 'documents'],
    ARRAY['equipment', 'maintenance'],
    ARRAY['form_submissions', 'forms'],
    ARRAY['gift_cards', 'pos'],
    ARRAY['goods_receipt_lines', 'purchasing'],
    ARRAY['goods_receipts', 'purchasing'],
    ARRAY['inventory_count_lines', 'inventory'],
    ARRAY['inventory_counts', 'inventory'],
    ARRAY['kb_article_revisions', 'knowledgeBase'],
    ARRAY['kb_articles', 'knowledgeBase'],
    ARRAY['landed_costs', 'inventory'],
    ARRAY['lead_activities', 'leads'],
    ARRAY['lead_email_blast_recipients', 'leads'],
    ARRAY['lead_email_blasts', 'leads'],
    ARRAY['leads', 'leads'],
    ARRAY['loyalty_accounts', 'pos'],
    ARRAY['loyalty_transactions', 'pos'],
    ARRAY['maintenance_requests', 'maintenance'],
    ARRAY['maintenance_schedules', 'maintenance'],
    ARRAY['mo_work_orders', 'manufacturing'],
    ARRAY['newsletter_email_opens', 'newsletter'],
    ARRAY['newsletter_link_clicks', 'newsletter'],
    ARRAY['newsletter_subscribers', 'newsletter'],
    ARRAY['newsletters', 'newsletter'],
    ARRAY['outbound_communications', 'email'],
    ARRAY['pipeline_stages', 'deals'],
    ARRAY['pos_payments', 'pos'],
    ARRAY['pos_sale_lines', 'pos'],
    ARRAY['pos_sales', 'pos'],
    ARRAY['pos_sessions', 'pos'],
    ARRAY['pos_tables', 'pos'],
    ARRAY['products', 'ecommerce'],
    ARRAY['project_milestones', 'projects'],
    ARRAY['project_task_dependencies', 'projects'],
    ARRAY['project_tasks', 'projects'],
    ARRAY['project_templates', 'projects'],
    ARRAY['purchase_order_lines', 'purchasing'],
    ARRAY['purchase_order_revisions', 'purchasing'],
    ARRAY['purchase_orders', 'purchasing'],
    ARRAY['quote_attachments', 'quotes'],
    ARRAY['quote_items', 'quotes'],
    ARRAY['quote_revisions', 'quotes'],
    ARRAY['quote_signatures', 'quotes'],
    ARRAY['quote_templates', 'quotes'],
    ARRAY['quote_versions', 'quotes'],
    ARRAY['quotes', 'quotes'],
    ARRAY['recurring_quote_templates', 'quotes'],
    ARRAY['rfq_bids', 'purchasing'],
    ARRAY['rfq_lines', 'purchasing'],
    ARRAY['rfqs', 'purchasing'],
    ARRAY['routing_operations', 'manufacturing'],
    ARRAY['service_credits', 'sla'],
    ARRAY['service_packages', 'fieldService'],
    ARRAY['shipping_pickups', 'shipping'],
    ARRAY['sla_clock_pauses', 'sla'],
    ARRAY['sla_tier_assignments', 'sla'],
    ARRAY['sla_tiers', 'sla'],
    ARRAY['stock_valuation_layers', 'inventory'],
    ARRAY['subscription_events', 'subscriptions'],
    ARRAY['subscription_plans', 'subscriptions'],
    ARRAY['subscriptions', 'subscriptions'],
    ARRAY['support_escalations', 'tickets'],
    ARRAY['ticket_comments', 'tickets'],
    ARRAY['ticket_escalation_rules', 'tickets'],
    ARRAY['ticket_team_members', 'tickets'],
    ARRAY['ticket_teams', 'tickets'],
    ARRAY['ticket_time_entries', 'tickets'],
    ARRAY['tickets', 'tickets'],
    ARRAY['vendor_credit_memos', 'purchasing'],
    ARRAY['vendor_invoice_disputes', 'purchasing'],
    ARRAY['vendors', 'purchasing'],
    ARRAY['webinars', 'webinars'],
    ARRAY['wiki_pages', 'wiki'],
    ARRAY['work_centers', 'manufacturing']
  ];
  pair text[];
  pol record;
  new_qual text;
  new_check text;
  n_rewritten int := 0;
  n_skipped int := 0;
BEGIN
  FOREACH pair SLICE 1 IN ARRAY MAP LOOP
    IF to_regclass('public.' || pair[1]) IS NULL THEN
      CONTINUE;
    END IF;
    FOR pol IN
      SELECT policyname, tablename, cmd, qual, with_check
        FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = pair[1]
         AND (qual LIKE '%is_staff(auth.uid())%' OR with_check LIKE '%is_staff(auth.uid())%')
    LOOP
      new_qual  := replace(pol.qual,       'is_staff(auth.uid())', format('can_access_module(auth.uid(), %L)', pair[2]));
      new_check := replace(pol.with_check, 'is_staff(auth.uid())', format('can_access_module(auth.uid(), %L)', pair[2]));
      IF pol.qual IS NOT NULL AND pol.with_check IS NOT NULL THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', pol.policyname, pol.tablename, new_qual, new_check);
      ELSIF pol.qual IS NOT NULL THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', pol.policyname, pol.tablename, new_qual);
      ELSE
        EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', pol.policyname, pol.tablename, new_check);
      END IF;
      n_rewritten := n_rewritten + 1;
    END LOOP;
  END LOOP;

  SELECT count(*) INTO n_skipped
    FROM pg_policies
   WHERE schemaname = 'public'
     AND (qual LIKE '%is_staff%' OR with_check LIKE '%is_staff%');

  RAISE NOTICE 'matrix-RLS: % policies rewritten to can_access_module; % is_staff policies remain (deliberate exceptions)', n_rewritten, n_skipped;
END $$;

-- === 20260813160000_flowtable-and-river-are-company-wide.sql ===
DO $$
DECLARE
  SHARED text[] := ARRAY['flowtable', 'river'];
  m text;
  r record;
BEGIN
  FOREACH m IN ARRAY SHARED LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT DISTINCT d.role, m
      FROM public.role_module_access_defaults d
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = d.role AND x.module_id = m
     );

    INSERT INTO public.role_module_access (role, module_id)
    SELECT DISTINCT a.role, m
      FROM public.role_module_access a
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = a.role AND x.module_id = m
     );
  END LOOP;

  FOR r IN
    SELECT module_id, count(*) AS n FROM public.role_module_access
     WHERE module_id = ANY(SHARED) GROUP BY module_id ORDER BY module_id
  LOOP
    RAISE NOTICE 'company-wide surface % → % role(s)', r.module_id, r.n;
  END LOOP;
END $$;

-- === 20260813180000_sales-owns-the-customer-lifecycle.sql ===
DO $$
DECLARE
  LIFECYCLE text[] := ARRAY['contracts', 'subscriptions', 'tickets'];
  m text;
  r record;
BEGIN
  FOREACH m IN ARRAY LIFECYCLE LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT 'sales', m
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = 'sales' AND x.module_id = m
     );

    INSERT INTO public.role_module_access (role, module_id)
    SELECT 'sales', m
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = 'sales' AND x.module_id = m
     );
  END LOOP;

  FOR r IN
    SELECT module_id FROM public.role_module_access
     WHERE role = 'sales' AND module_id = ANY(LIFECYCLE) ORDER BY module_id
  LOOP
    RAISE NOTICE 'sales lifecycle grant: %', r.module_id;
  END LOOP;
END $$;

-- === 20260813200000_email-trust-and-suppression.sql ===
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS email_confidence integer,
  ADD COLUMN IF NOT EXISTS email_status text DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS email_provenance jsonb;

COMMENT ON COLUMN public.leads.email_status IS
  'unverified | valid | invalid | accept_all | webmail | disposable | unknown — Hunter verifier vocabulary. Send gate: invalid/disposable block, accept_all/unknown warn.';

-- === 20260813230000_subscription-amount-is-per-period-not-tcv.sql ===
CREATE OR REPLACE FUNCTION public.create_subscription_from_contract(p_contract_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  c public.contracts%ROWTYPE;
  v_sub_id uuid;
  v_months int;
  v_interval text;
  v_count int;
  v_periods numeric;
  v_unit_cents bigint;
BEGIN
  SELECT * INTO c FROM public.contracts WHERE id = p_contract_id;
  IF c.id IS NULL THEN
    RAISE EXCEPTION 'Contract not found: %', p_contract_id;
  END IF;

  SELECT id INTO v_sub_id FROM public.subscriptions WHERE contract_id = p_contract_id;
  IF v_sub_id IS NOT NULL THEN
    RETURN v_sub_id;
  END IF;

  v_months := CASE
    WHEN c.start_date IS NOT NULL AND c.end_date IS NOT NULL
      THEN GREATEST(1, (date_part('year', age(c.end_date, c.start_date)) * 12
                        + date_part('month', age(c.end_date, c.start_date)))::int)
    ELSE NULL
  END;
  v_interval := COALESCE(NULLIF(c.billing_interval, ''), 'month');
  v_count := COALESCE(c.billing_interval_count, 1);

  IF c.billing_amount_cents IS NOT NULL THEN
    v_unit_cents := c.billing_amount_cents;
  ELSIF c.value_cents IS NOT NULL THEN
    v_periods := CASE v_interval
      WHEN 'week'    THEN CASE WHEN c.start_date IS NOT NULL AND c.end_date IS NOT NULL
                                THEN (c.end_date - c.start_date)::numeric / (7 * v_count)
                                ELSE NULL END
      WHEN 'month'   THEN v_months::numeric / (1 * v_count)
      WHEN 'quarter' THEN v_months::numeric / (3 * v_count)
      WHEN 'year'    THEN v_months::numeric / (12 * v_count)
      ELSE NULL
    END;
    v_unit_cents := CASE WHEN v_periods IS NOT NULL AND v_periods >= 1
                         THEN round(c.value_cents / v_periods)
                         ELSE 0 END;
  ELSE
    v_unit_cents := 0;
  END IF;

  INSERT INTO public.subscriptions (
    customer_email, customer_name, status,
    unit_amount_cents, currency,
    billing_interval, billing_interval_count,
    provider, contract_id,
    commitment_start, commitment_months, commitment_end,
    current_period_start, current_period_end,
    product_name
  )
  VALUES (
    c.counterparty_email, c.counterparty_name,
    'provisioning',
    v_unit_cents, COALESCE(c.currency, 'SEK'),
    v_interval, v_count,
    'contract', c.id,
    c.start_date, v_months,
    CASE WHEN c.start_date IS NOT NULL AND v_months IS NOT NULL
         THEN c.start_date + (v_months || ' months')::interval
         ELSE c.end_date END,
    c.start_date, c.billing_next_date,
    c.title
  )
  RETURNING id INTO v_sub_id;

  RETURN v_sub_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_subscription_from_contract(uuid)
  TO authenticated, service_role;

-- === 20260813250000_fit-analysis-survives-the-tab.sql ===
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS fit_score integer,
  ADD COLUMN IF NOT EXISTS fit_analysis jsonb,
  ADD COLUMN IF NOT EXISTS fit_analyzed_at timestamptz;

COMMENT ON COLUMN public.companies.fit_analysis IS
  'Latest prospect fit assessment (FitAnalysisResult shape from Sales Intelligence). Superseded in place; run history lives in agent_activity.';

-- === 20260813260000_research-keeps-what-it-read.sql ===
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS web_summary text;

COMMENT ON COLUMN public.companies.web_summary IS
  'What prospect research read on their website (scraped excerpt or AI distillation). Refreshed on each research run; grounds fit analysis and outreach.';

-- === 20260813270000_raw-research-material-is-an-asset.sql ===
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS web_raw jsonb;

COMMENT ON COLUMN public.companies.web_raw IS
  'Raw scraped material from research/enrich: { url, fetched_at, provider, content, search_snippets }. Archive for re-distillation and breadth search; web_summary is the distilled working set.';