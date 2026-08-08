-- Portal ticket (a service the customer holds → an issue they can raise) and
-- service delivery as a status. Two builds Magnus confirmed 2026-08-07.
--
-- A ticket IS a thing the customer refers to, so a ticket number is justified
-- under the AliExpress rule — unlike an order number, which would just double
-- the agreement number. TIC-YYYY-NNNNN, via next_document_number like AGR/INV.

-- ── ticket_number ───────────────────────────────────────────────────────────
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

-- Backfill existing tickets so the column is never half-populated.
UPDATE public.tickets SET ticket_number = public.next_document_number('ticket', 'TIC')
WHERE ticket_number IS NULL;

-- ── create_ticket_from_portal ───────────────────────────────────────────────
-- The customer stands on their service card and describes the PROBLEM; the
-- system supplies the CONTEXT. Never trusts client-passed identity: the email
-- comes from the JWT, the company and service from the subscription the caller
-- actually owns. So a customer cannot open a ticket "as" someone else or
-- against a service that isn't theirs.
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

  -- If a service is named, it must belong to the caller — bind its company,
  -- and refuse a service the caller does not own (no cross-customer tickets).
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

-- ── service delivery = a status flip, never a new number ────────────────────
-- Contract-born services start 'provisioning' (signed, delivery pending) and
-- staff mark them delivered → 'active'. The customer sees the state on their
-- card; no order object, no order number.
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

-- Contract-born services now start pending delivery. The one-invoicer rule is
-- unaffected — the contract bills regardless of the service's delivery status.
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
    -- Signed, awaiting delivery. Staff flip to 'active' via mark_service_delivered.
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
