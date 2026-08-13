-- #172: the TCV fallback showed the whole contract value as a monthly amount.
--
-- After the cadence model, contracts.value_cents IS the TCV (total contract
-- value) while billing_amount_cents is the per-period amount. The old fallback
--   COALESCE(billing_amount_cents, value_cents, 0)
-- therefore put a dimensionally wrong number into subscriptions.unit_amount_cents
-- whenever a contract was signed without an explicit billing amount: a 120 000 kr
-- two-year contract read as 120 000 kr/month in the customer portal. No invoice
-- could go wrong (generate_contract_invoice refuses without billing_amount_cents)
-- — the lie was display-only, but it was the first thing a paying customer saw.
--
-- Fix: when billing_amount_cents is missing, project the TCV down to one period
-- using the commitment span and the billing cadence — the same dimensioned
-- arithmetic the value model uses everywhere else. If the span is unknown the
-- amount is 0 ("not set"), never the TCV.

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
    -- TCV → per period. Number of periods over the commitment span:
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
    -- Signed, awaiting delivery. Staff flip to 'active' via mark_service_delivered.
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
