-- ===== on_invoice_status_book =====
CREATE OR REPLACE FUNCTION public.on_invoice_status_book()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'sent' THEN
      PERFORM public.book_invoice_issued(NEW.id);
    ELSIF NEW.status = 'paid' THEN
      PERFORM public.book_invoice_paid(NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

-- ===== record_invoice_payment =====
CREATE OR REPLACE FUNCTION "public"."record_invoice_payment"(
  "p_invoice_id" "uuid",
  "p_amount_cents" bigint,
  "p_method" "text" DEFAULT 'manual',
  "p_paid_at" timestamptz DEFAULT now()
) RETURNS "jsonb"
LANGUAGE "plpgsql" SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
  v_inv RECORD;
  v_remaining bigint;
  v_new_paid bigint;
  v_fully boolean;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'approver')) THEN
    RAISE EXCEPTION 'Not authorized to record payments';
  END IF;
  IF p_amount_cents <= 0 THEN RAISE EXCEPTION 'p_amount_cents must be positive'; END IF;

  SELECT id, total_cents, COALESCE(paid_amount_cents,0) AS paid_amount_cents, status, invoice_type
    INTO v_inv FROM invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invoice % not found', p_invoice_id; END IF;
  IF v_inv.status::text = 'cancelled' THEN RAISE EXCEPTION 'Cannot pay a cancelled invoice'; END IF;
  IF COALESCE(v_inv.invoice_type,'invoice') <> 'invoice' THEN RAISE EXCEPTION 'Cannot pay a credit note'; END IF;

  v_remaining := GREATEST(0, v_inv.total_cents - v_inv.paid_amount_cents);
  IF p_amount_cents > v_remaining THEN
    RAISE EXCEPTION 'Payment % exceeds remaining balance %', p_amount_cents, v_remaining;
  END IF;

  v_new_paid := v_inv.paid_amount_cents + p_amount_cents;
  v_fully := (v_new_paid >= v_inv.total_cents);

  UPDATE invoices
    SET paid_amount_cents = v_new_paid,
        status = CASE WHEN v_fully THEN 'paid'::invoice_status ELSE status END,
        paid_at = CASE WHEN v_fully THEN COALESCE(paid_at, p_paid_at) ELSE paid_at END
  WHERE id = p_invoice_id;

  INSERT INTO audit_logs (action, entity_type, entity_id, user_id, metadata)
  VALUES ('invoice.payment_recorded', 'invoice', p_invoice_id, auth.uid(),
    jsonb_build_object('amount_cents', p_amount_cents, 'method', p_method,
      'paid_amount_cents', v_new_paid, 'fully_paid', v_fully));

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id,
    'amount_cents', p_amount_cents, 'paid_amount_cents', v_new_paid,
    'remaining_cents', GREATEST(0, v_inv.total_cents - v_new_paid),
    'fully_paid', v_fully,
    'status', CASE WHEN v_fully THEN 'paid' ELSE v_inv.status::text END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.book_invoice_paid(p_invoice_id uuid, p_bank_account text DEFAULT NULL::text, p_ar_account text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inv record;
  v_entry_id uuid;
  v_amount bigint;
BEGIN
  p_bank_account := COALESCE(p_bank_account, public.account_for('bank'));
  p_ar_account := COALESCE(p_ar_account, public.account_for('accounts_receivable'));
  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found');
  END IF;

  IF EXISTS (SELECT 1 FROM journal_entries WHERE invoice_id = p_invoice_id AND source = 'invoice_payment') THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'already booked');
  END IF;

  v_amount := COALESCE(v_inv.paid_amount_cents, v_inv.total_cents, 0);
  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Paid amount is zero');
  END IF;

  PERFORM public.book_invoice_issued(p_invoice_id);

  INSERT INTO journal_entries (entry_date, description, source, invoice_id, status)
  VALUES (COALESCE(v_inv.paid_at::date, CURRENT_DATE),
          'Invoice ' || COALESCE(v_inv.invoice_number, p_invoice_id::text) || ' paid',
          'invoice_payment', p_invoice_id, 'posted')
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES (v_entry_id, p_bank_account, v_amount, 0, 'Bank');
  INSERT INTO journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES (v_entry_id, p_ar_account, 0, v_amount, 'Settle accounts receivable');

  RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id, 'journal_entry_id', v_entry_id, 'amount_cents', v_amount);
END;
$function$;

CREATE OR REPLACE FUNCTION public.book_invoice_issued(p_invoice_id uuid, p_ar_account text DEFAULT NULL::text, p_revenue_account text DEFAULT NULL::text, p_vat_account text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inv record;
  v_entry_id uuid;
  v_net bigint;
  v_vat bigint;
  v_total bigint;
BEGIN
  p_ar_account := COALESCE(p_ar_account, public.account_for('accounts_receivable'));
  p_revenue_account := COALESCE(p_revenue_account, public.account_for('sales_revenue'));
  p_vat_account := COALESCE(p_vat_account, public.account_for('vat_output'));
  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found');
  END IF;

  IF EXISTS (SELECT 1 FROM journal_entries WHERE invoice_id = p_invoice_id AND source = 'invoice_issued') THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'already booked');
  END IF;

  v_total := COALESCE(v_inv.total_cents, 0);
  v_vat   := COALESCE(v_inv.tax_cents, 0);
  v_net   := COALESCE(v_inv.subtotal_cents, v_total - v_vat);
  IF v_total <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice total is zero');
  END IF;

  INSERT INTO journal_entries (entry_date, description, source, invoice_id, status)
  VALUES (COALESCE(v_inv.issue_date, CURRENT_DATE),
          'Invoice ' || COALESCE(v_inv.invoice_number, p_invoice_id::text) || ' issued',
          'invoice_issued', p_invoice_id, 'posted')
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES (v_entry_id, p_ar_account, v_total, 0, 'Accounts receivable');
  INSERT INTO journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES (v_entry_id, p_revenue_account, 0, v_net, 'Revenue');
  IF v_vat > 0 THEN
    INSERT INTO journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
    VALUES (v_entry_id, p_vat_account, 0, v_vat, 'Output VAT');
  END IF;

  RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id, 'journal_entry_id', v_entry_id, 'total_cents', v_total);
END;
$function$;

-- ===== document numbering =====
CREATE TABLE IF NOT EXISTS public.document_counters (
  kind text PRIMARY KEY,
  last_value integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.document_counters TO authenticated;
GRANT ALL ON public.document_counters TO service_role;
ALTER TABLE public.document_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff can view document counters" ON public.document_counters;
CREATE POLICY "Staff can view document counters" ON public.document_counters
  FOR SELECT TO authenticated USING (has_role(auth.uid(), 'admin'::app_role));

INSERT INTO public.document_counters (kind, last_value)
SELECT 'invoice', COALESCE(MAX(NULLIF(regexp_replace(invoice_number, '\D', '', 'g'), '')::int), 0)
FROM public.invoices
ON CONFLICT (kind) DO NOTHING;

INSERT INTO public.document_counters (kind, last_value)
SELECT 'quote', COALESCE(MAX(NULLIF(regexp_replace(quote_number, '\D', '', 'g'), '')::int), 0)
FROM public.quotes
ON CONFLICT (kind) DO NOTHING;

CREATE OR REPLACE FUNCTION public.next_document_number(p_kind text, p_prefix text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
BEGIN
  INSERT INTO public.document_counters (kind, last_value)
  VALUES (p_kind, 1)
  ON CONFLICT (kind)
  DO UPDATE SET last_value = document_counters.last_value + 1, updated_at = now()
  RETURNING last_value INTO v_seq;
  RETURN p_prefix || '-' || lpad(v_seq::text, 4, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.next_document_number(text, text) TO service_role, authenticated, anon;

-- ===== subscription billing sweep =====
CREATE OR REPLACE FUNCTION public.run_subscription_billing()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _trial jsonb;
  _trial_error text := NULL;
  _sub record;
  _res jsonb;
  _results jsonb := '[]'::jsonb;
  _ok integer := 0;
  _failed integer := 0;
  _candidates integer := 0;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role) OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Only admins or system can run subscription billing';
  END IF;

  BEGIN
    _trial := public.run_trial_conversions();
  EXCEPTION WHEN OTHERS THEN
    _trial_error := SQLERRM;
  END;

  FOR _sub IN
    SELECT id
      FROM public.subscriptions
     WHERE provider = 'manual'
       AND status = 'active'::subscription_status
       AND next_invoice_date <= CURRENT_DATE
     ORDER BY next_invoice_date
     LIMIT 500
  LOOP
    _candidates := _candidates + 1;
    BEGIN
      _res := public.generate_subscription_invoice(_sub.id);
      _ok := _ok + 1;
      _results := _results || jsonb_build_object(
        'subscription_id', _sub.id,
        'ok', true,
        'invoice_id', _res->>'invoice_id',
        'invoice_number', _res->>'invoice_number'
      );
    EXCEPTION WHEN OTHERS THEN
      _failed := _failed + 1;
      _results := _results || jsonb_build_object(
        'subscription_id', _sub.id,
        'ok', false,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'run_at', now(),
    'trial_sweep', _trial,
    'trial_error', _trial_error,
    'candidates', _candidates,
    'succeeded', _ok,
    'failed', _failed,
    'results', _results
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.run_subscription_billing() TO authenticated, service_role;

-- ===== contract billing sweep =====
CREATE OR REPLACE FUNCTION public.run_contract_billing()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _c record;
  _res jsonb;
  _results jsonb := '[]'::jsonb;
  _ok integer := 0;
  _failed integer := 0;
  _candidates integer := 0;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role) OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Only admins or system can run contract billing';
  END IF;

  FOR _c IN
    SELECT id, title
      FROM public.contracts
     WHERE status = 'active'
       AND billing_enabled IS TRUE
       AND billing_next_date IS NOT NULL
       AND billing_next_date <= CURRENT_DATE
     ORDER BY billing_next_date
     LIMIT 500
  LOOP
    _candidates := _candidates + 1;
    BEGIN
      _res := public.generate_contract_invoice(_c.id);
      _ok := _ok + 1;
      _results := _results || jsonb_build_object(
        'contract_id', _c.id,
        'title', _c.title,
        'ok', true,
        'invoice_id', _res->>'invoice_id',
        'invoice_number', _res->>'invoice_number'
      );
    EXCEPTION WHEN OTHERS THEN
      _failed := _failed + 1;
      _results := _results || jsonb_build_object(
        'contract_id', _c.id,
        'title', _c.title,
        'ok', false,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'run_at', now(),
    'candidates', _candidates,
    'succeeded', _ok,
    'failed', _failed,
    'results', _results,
    'note', 'Invoicing only. Payment reminders still run from the contract-billing-cron edge function.'
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.run_contract_billing() TO authenticated, service_role;