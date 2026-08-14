-- === 20260813220000_business-identity-belongs-to-the-message-owners.sql ===
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'site_settings'
       AND policyname = 'Company profile editable by its module roles'
  ) THEN
    CREATE POLICY "Company profile editable by its module roles" ON public.site_settings
      FOR UPDATE
      USING (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'))
      WITH CHECK (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'site_settings'
       AND policyname = 'Company profile creatable by its module roles'
  ) THEN
    CREATE POLICY "Company profile creatable by its module roles" ON public.site_settings
      FOR INSERT
      WITH CHECK (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'));
  END IF;
END $$;

DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['sales', 'accounting', 'marketing'] LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT r::app_role, 'companyInsights'
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = r::app_role AND x.module_id = 'companyInsights'
     );
    INSERT INTO public.role_module_access (role, module_id)
    SELECT r::app_role, 'companyInsights'
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = r::app_role AND x.module_id = 'companyInsights'
     );
  END LOOP;
END $$;

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