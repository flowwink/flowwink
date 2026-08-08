ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS contract_id uuid REFERENCES public.contracts(id) ON DELETE SET NULL;

ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_contract_id_uniq
  ON public.subscriptions(contract_id) WHERE contract_id IS NOT NULL;

ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS ticket_number text;

CREATE OR REPLACE FUNCTION public.tickets_assign_number()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.ticket_number IS NULL THEN
    NEW.ticket_number := public.next_document_number('ticket', 'TIC');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tickets_assign_number ON public.tickets;
CREATE TRIGGER tickets_assign_number
  BEFORE INSERT ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.tickets_assign_number();

UPDATE public.tickets SET ticket_number = public.next_document_number('ticket', 'TIC')
WHERE ticket_number IS NULL;

DROP FUNCTION IF EXISTS public.create_ticket_from_portal(text, text, uuid, public.ticket_priority);
CREATE FUNCTION public.create_ticket_from_portal(
  p_subject text,
  p_description text,
  p_subscription_id uuid DEFAULT NULL,
  p_priority public.ticket_priority DEFAULT 'medium'
)
RETURNS TABLE(ticket_id uuid, ticket_no text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_company uuid;
  v_sub public.subscriptions%ROWTYPE;
  v_new_id uuid;
  v_num text;
BEGIN
  IF auth.uid() IS NULL OR v_email = '' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF coalesce(trim(p_subject), '') = '' THEN
    RAISE EXCEPTION 'A subject is required';
  END IF;

  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub FROM public.subscriptions WHERE id = p_subscription_id;
    IF v_sub.id IS NULL OR lower(coalesce(v_sub.customer_email, '')) <> v_email THEN
      RAISE EXCEPTION 'That service is not on your account';
    END IF;
    IF v_sub.contract_id IS NOT NULL THEN
      SELECT company_id INTO v_company FROM public.contracts WHERE id = v_sub.contract_id;
    END IF;
  END IF;

  INSERT INTO public.tickets (
    subject, description, status, priority,
    contact_email, subscription_id, company_id, source, created_by
  )
  VALUES (
    trim(p_subject), p_description, 'new', p_priority,
    v_email, p_subscription_id, v_company, 'portal', auth.uid()
  )
  RETURNING tickets.id, tickets.ticket_number INTO v_new_id, v_num;

  RETURN QUERY SELECT v_new_id, v_num;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_ticket_from_portal(text, text, uuid, public.ticket_priority)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_service_delivered(p_subscription_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT (auth.role() = 'service_role' OR is_staff(auth.uid())) THEN
    RAISE EXCEPTION 'Only staff can mark a service delivered';
  END IF;
  UPDATE public.subscriptions
  SET status = 'active', current_period_start = coalesce(current_period_start, CURRENT_DATE)
  WHERE id = p_subscription_id AND status = 'provisioning';
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_service_delivered(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_subscription_from_contract(p_contract_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  c public.contracts%ROWTYPE;
  v_sub_id uuid;
  v_months int;
  v_interval text;
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
    COALESCE(c.billing_amount_cents, c.value_cents, 0), COALESCE(c.currency, 'SEK'),
    v_interval, COALESCE(c.billing_interval_count, 1),
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