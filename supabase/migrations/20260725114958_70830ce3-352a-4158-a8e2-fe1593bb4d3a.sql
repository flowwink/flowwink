ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS reverse_charge_rate numeric;

INSERT INTO public.account_roles (locale, role, account_code)
VALUES
  ('se-bas2024', 'vat_input_reverse', '2645'),
  ('se-bas2024', 'vat_output_reverse_25', '2614'),
  ('se-bas2024', 'vat_output_reverse_12', '2624'),
  ('se-bas2024', 'vat_output_reverse_6', '2634')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.book_expense_report(
  p_report_id uuid,
  p_expense_account text DEFAULT '5410'::text,
  p_vat_account text DEFAULT '2641'::text,
  p_liability_account text DEFAULT '2890'::text,
  p_entry_date date DEFAULT NULL::date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_report record;
  v_total_cents bigint;
  v_vat_cents bigint;
  v_net_cents bigint;
  v_rc_base_cents bigint;
  v_rc_vat_25 bigint;
  v_rc_vat_12 bigint;
  v_rc_vat_6 bigint;
  v_rc_vat_total bigint;
  v_entry_id uuid;
  v_date date;
  v_rc_input_account text;
BEGIN
  SELECT * INTO v_report FROM expense_reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found');
  END IF;
  IF v_report.status <> 'approved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only approved reports can be booked');
  END IF;

  SELECT COALESCE(SUM(amount_cents),0), COALESCE(SUM(vat_cents),0)
  INTO v_total_cents, v_vat_cents
  FROM expenses WHERE report_id = p_report_id;

  SELECT
    COALESCE(SUM(amount_cents - vat_cents), 0),
    COALESCE(SUM(CASE WHEN reverse_charge_rate = 25 THEN round((amount_cents - vat_cents) * 0.25) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN reverse_charge_rate = 12 THEN round((amount_cents - vat_cents) * 0.12) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN reverse_charge_rate = 6  THEN round((amount_cents - vat_cents) * 0.06) ELSE 0 END), 0)
  INTO v_rc_base_cents, v_rc_vat_25, v_rc_vat_12, v_rc_vat_6
  FROM expenses
  WHERE report_id = p_report_id
    AND COALESCE(reverse_charge_rate, 0) > 0;

  v_rc_vat_total := v_rc_vat_25 + v_rc_vat_12 + v_rc_vat_6;
  v_net_cents := v_total_cents - v_vat_cents;
  v_date := COALESCE(p_entry_date, CURRENT_DATE);
  v_rc_input_account := COALESCE(public.account_for('vat_input_reverse'), '2645');

  INSERT INTO journal_entries (entry_date, description, source, status)
  VALUES (v_date, 'Expense report ' || p_report_id::text, 'expense_report', 'posted')
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_entry_lines (journal_entry_id, account_code, account_name, debit_cents, credit_cents, description)
  SELECT v_entry_id, x.code, COALESCE(coa.account_name, x.code), x.deb, x.cred, x.descr
  FROM (VALUES
    (p_expense_account,   v_net_cents,   0::bigint,      'Expense (net)'),
    (p_vat_account,       v_vat_cents,   0::bigint,      'Input VAT'),
    (p_liability_account, 0::bigint,     v_total_cents,  'Liability to employee')
  ) AS x(code, deb, cred, descr)
  LEFT JOIN chart_of_accounts coa ON coa.account_code = x.code
  WHERE x.deb <> 0 OR x.cred <> 0;

  IF v_rc_vat_total > 0 THEN
    INSERT INTO journal_entry_lines (journal_entry_id, account_code, account_name, debit_cents, credit_cents, description)
    SELECT v_entry_id, x.code, COALESCE(coa.account_name, x.code), x.deb, x.cred, x.descr
    FROM (VALUES
      (v_rc_input_account, v_rc_vat_total, 0::bigint, 'Calculated input VAT (reverse charge)'),
      (COALESCE(public.account_for('vat_output_reverse_25'), '2614'), 0::bigint, v_rc_vat_25, 'Calculated output VAT reverse charge 25%'),
      (COALESCE(public.account_for('vat_output_reverse_12'), '2624'), 0::bigint, v_rc_vat_12, 'Calculated output VAT reverse charge 12%'),
      (COALESCE(public.account_for('vat_output_reverse_6'),  '2634'), 0::bigint, v_rc_vat_6,  'Calculated output VAT reverse charge 6%')
    ) AS x(code, deb, cred, descr)
    LEFT JOIN chart_of_accounts coa ON coa.account_code = x.code
    WHERE x.deb <> 0 OR x.cred <> 0;
  END IF;

  UPDATE expense_reports
  SET status = 'booked', journal_entry_id = v_entry_id
  WHERE id = p_report_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_id', p_report_id,
    'journal_entry_id', v_entry_id,
    'total_cents', v_total_cents,
    'reverse_charge_base_cents', v_rc_base_cents,
    'reverse_charge_vat_cents', v_rc_vat_total
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_vat_return(p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_out_25 bigint; v_out_12 bigint; v_out_6 bigint; v_out_rc bigint;
  v_input bigint; v_output bigint; v_net bigint;
BEGIN
  SELECT
    COALESCE(SUM(CASE WHEN l.account_code IN ('2610','2611','2612','2613') THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.account_code IN ('2620','2621','2622','2623') THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.account_code IN ('2630','2631','2632','2633') THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.account_code IN ('2614','2615','2616','2617','2624','2625','2634','2635') THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.account_code IN ('2640','2641','2645') THEN l.debit_cents - l.credit_cents ELSE 0 END), 0)
  INTO v_out_25, v_out_12, v_out_6, v_out_rc, v_input
  FROM public.journal_entry_lines l
  JOIN public.journal_entries e ON e.id = l.journal_entry_id
  WHERE e.entry_date BETWEEN p_from AND p_to
    AND e.status = 'posted';

  v_output := v_out_25 + v_out_12 + v_out_6 + v_out_rc;
  v_net := v_output - v_input;

  RETURN jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to),
    'output_vat_cents', jsonb_build_object(
      'standard_25', v_out_25, 'reduced_12', v_out_12, 'reduced_6', v_out_6,
      'reverse_charge', v_out_rc, 'total', v_output
    ),
    'input_vat_cents', v_input,
    'net_to_pay_cents', v_net,
    'net_to_pay_sek', round(v_net / 100.0, 2),
    'direction', CASE WHEN v_net >= 0 THEN 'pay_to_skatteverket' ELSE 'refund_from_skatteverket' END,
    'note', 'Sums posted journal lines on the VAT accounts (2610-2613/2620-2623/2630-2633 output, 2614-2617/2624-2625/2634-2635 reverse charge, 2640/2641/2645 input). Verify against the VAT control account (2650) before filing.'
  );
END;
$function$;