-- The templates asked for [KUNDENS ORGNR]; the platform already knew it.
--
-- companies.org_number has existed since the B2B master-data work and
-- contracts has carried company_id all along — but create_contract_from_template
-- never looked. Every agreement drafted from a template shipped with a bracket
-- placeholder for a value sitting one join away.
--
-- The renderer now resolves the counterparty's company (explicit override →
-- company_id in overrides → case-insensitive name match) and substitutes both
-- the token {{counterparty.org_number}} AND the literal [KUNDENS ORGNR]
-- bracket. Substituting the bracket is deliberate: all existing templates
-- benefit without editing, and when the number is NOT known the bracket stays
-- visibly unfilled — a missing value must look missing, never render as empty.

CREATE OR REPLACE FUNCTION public.create_contract_from_template(
  p_template_id uuid,
  p_counterparty_name text,
  p_counterparty_email text DEFAULT NULL,
  p_overrides jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE (contract_id uuid, title text, status public.contract_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl public.contract_templates%ROWTYPE;
  v_body text;
  v_title text;
  v_start date;
  v_end date;
  v_value bigint;
  v_currency text;
  v_company_id uuid;
  v_org text;
  v_new_id uuid;
BEGIN
  SELECT * INTO v_tpl FROM public.contract_templates WHERE id = p_template_id;
  IF v_tpl.id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_id;
  END IF;

  v_start := COALESCE((p_overrides->>'start_date')::date, CURRENT_DATE);
  v_end := NULLIF(p_overrides->>'end_date', '')::date;
  v_value := COALESCE((p_overrides->>'value_cents')::bigint, v_tpl.default_value_cents);
  v_currency := COALESCE(p_overrides->>'currency', v_tpl.default_currency);
  v_title := COALESCE(p_overrides->>'title', v_tpl.name || ' — ' || p_counterparty_name);

  -- Resolve the counterparty's company: explicit id wins, then a
  -- case-insensitive name match against master data.
  v_company_id := CASE WHEN (p_overrides->>'company_id') ~* '^[0-9a-f-]{36}$'
                       THEN (p_overrides->>'company_id')::uuid END;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.companies
    WHERE lower(name) = lower(trim(p_counterparty_name)) LIMIT 1;
  END IF;

  v_org := COALESCE(
    NULLIF(trim(p_overrides->>'org_number'), ''),
    (SELECT org_number FROM public.companies WHERE id = v_company_id)
  );

  v_body := v_tpl.body_markdown;
  v_body := replace(v_body, '{{counterparty.name}}', p_counterparty_name);
  v_body := replace(v_body, '{{counterparty.email}}', COALESCE(p_counterparty_email, ''));
  v_body := replace(v_body, '{{today}}', to_char(CURRENT_DATE, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{start_date}}', to_char(v_start, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{end_date}}', COALESCE(to_char(v_end, 'YYYY-MM-DD'), 'TBD'));
  v_body := replace(v_body, '{{value}}', to_char(v_value / 100.0, 'FM999G999G999D00'));
  v_body := replace(v_body, '{{currency}}', v_currency);
  v_body := replace(v_body, '{{title}}', v_title);

  IF v_org IS NOT NULL THEN
    v_body := replace(v_body, '{{counterparty.org_number}}', v_org);
    v_body := replace(v_body, '[KUNDENS ORGNR]', v_org);
  END IF;
  -- When unknown: token collapses to the visible bracket so the gap is seen.
  v_body := replace(v_body, '{{counterparty.org_number}}', '[KUNDENS ORGNR]');

  -- Column set preserved from the previous definition (template provenance:
  -- template_id, version, body_updated_at) — company_id is the one addition.
  INSERT INTO public.contracts
    (title, counterparty_name, counterparty_email, contract_type, status,
     company_id, start_date, end_date, value_cents, currency,
     renewal_type, renewal_notice_days,
     body_markdown, body_updated_at, template_id, version)
  VALUES
    (v_title, p_counterparty_name, p_counterparty_email, v_tpl.contract_type, 'draft',
     v_company_id, v_start, v_end, v_value, v_currency,
     v_tpl.default_renewal_type, v_tpl.default_renewal_notice_days,
     v_body, now(), p_template_id, 1)
  RETURNING id INTO v_new_id;

  RETURN QUERY SELECT c.id, c.title, c.status FROM public.contracts c WHERE c.id = v_new_id;
END;
$$;
