-- VAT return value boxes: purchase accounts + per-line expense posting.
--
-- After the reverse-charge fix (20260726090000) the VAT AMOUNT boxes (30, 48)
-- are right, but the purchase-VALUE boxes still read zero, because:
--   1. the 45xx purchase accounts do not exist in chart_of_accounts, and
--   2. book_expense_report ignored each expense line's own `account_code` and
--      lumped the whole report onto one p_expense_account — so nothing could
--      ever land on a 45xx account even if you asked for it.
--
-- (1) and (2) are fixed here. The box map itself is TypeScript and is corrected
-- alongside this migration.
--
-- BAS 2024 split, which the old box map got wrong by lumping them together:
--   4531-4534  Inköp av tjänster från land UTANFÖR EU   → SKV box 22
--   4535-4538  Inköp av tjänster från annat EU-land     → SKV box 21
-- A US SaaS subscription is 4531, not 4535 — that distinction is the whole
-- reason box 22 exists. Verify the mapping with your accountant before filing.

-- ─── 1. Purchase accounts the value boxes read ──────────────────────────────
INSERT INTO public.chart_of_accounts
  (account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
SELECT v.*
-- REPLAY GUARD (2026-08-13): was ON CONFLICT (account_code) — names the unique
-- constraint of this file's era; the locale work replaced it with
-- UNIQUE (locale, account_code), so replay onto a newer schema was 42P10.
FROM (VALUES
  -- Goods from another EU country (box 20)
  ('4515', 'Inköp av varor från annat EU-land, 25% moms',    'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4516', 'Inköp av varor från annat EU-land, 12% moms',    'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4517', 'Inköp av varor från annat EU-land, 6% moms',     'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4518', 'Inköp av varor från annat EU-land, momsfri',     'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  -- Services from OUTSIDE the EU (box 22) — where foreign SaaS belongs
  ('4531', 'Inköp av tjänster från land utanför EU, 25% moms', 'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4532', 'Inköp av tjänster från land utanför EU, 12% moms', 'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4533', 'Inköp av tjänster från land utanför EU, 6% moms',  'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4534', 'Inköp av tjänster från land utanför EU, momsfri',  'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  -- Services from another EU country (box 21)
  ('4535', 'Inköp av tjänster från annat EU-land, 25% moms',   'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4536', 'Inköp av tjänster från annat EU-land, 12% moms',   'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4537', 'Inköp av tjänster från annat EU-land, 6% moms',    'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4538', 'Inköp av tjänster från annat EU-land, momsfri',    'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  -- Imported goods (box 50)
  ('4545', 'Import av varor, 25% moms',                        'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4546', 'Import av varor, 12% moms',                        'expense', 'kostnader', 'debit', true, 'se-bas2024'),
  ('4547', 'Import av varor, 6% moms',                         'expense', 'kostnader', 'debit', true, 'se-bas2024')
) AS v(account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
WHERE NOT EXISTS (
  SELECT 1 FROM public.chart_of_accounts c
   WHERE c.account_code = v.account_code AND c.locale = v.locale
)
-- COUNTRY GUARD (2026-08-22, se 20260822234500): fifteen Swedish purchase
-- accounts were the single largest reason a brand-new install anywhere in the
-- world woke up with a half-Swedish chart. They exist to make the SKV value
-- boxes readable; an instance with no activated locale files no SKV return.
AND (
  EXISTS (
    SELECT 1 FROM public.site_settings s
     WHERE s.key = 'accounting_locale'
       AND COALESCE(s.value ->> 'id', NULLIF(s.value #>> '{}', '')) = 'se-bas2024'
  )
  OR EXISTS (
    SELECT 1 FROM public.journal_entry_lines l WHERE l.account_code = v.account_code
  )
);

-- ─── 2. Respect each line's own account ─────────────────────────────────────
-- The expense line already carries `account_code`; the booker threw it away.
-- Honouring it is what lets a purchase land on 4531 and light up box 22 — no
-- new inference, no new field: the caller declares the account, as before.
CREATE OR REPLACE FUNCTION public.book_expense_report(
  p_report_id uuid,
  p_expense_account text DEFAULT NULL,
  p_vat_account text DEFAULT NULL,
  p_liability_account text DEFAULT NULL,
  p_entry_date date DEFAULT NULL
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
  v_entry_id uuid;
  v_date date;
  v_acct record;
  v_rc record;
  v_rc_input text;
  v_rc_output text;
  v_rc_vat bigint;
  v_rc_total bigint := 0;
  v_rc_skipped jsonb := '[]'::jsonb;
  v_locale text;
BEGIN
  p_expense_account := COALESCE(p_expense_account, public.account_for('expense_default'));
  p_vat_account := COALESCE(p_vat_account, public.account_for('vat_input'));
  p_liability_account := COALESCE(p_liability_account, public.account_for('employee_liability'));
  SELECT * INTO v_report FROM public.expense_reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found');
  END IF;
  IF v_report.status <> 'approved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only approved reports can be booked');
  END IF;

  SELECT COALESCE(SUM(amount_cents),0), COALESCE(SUM(vat_cents),0)
  INTO v_total_cents, v_vat_cents
  FROM public.expenses WHERE report_id = p_report_id;

  v_date := COALESCE(p_entry_date, CURRENT_DATE);

  INSERT INTO public.journal_entries (entry_date, description, source, status)
  VALUES (v_date, 'Expense report ' || p_report_id::text, 'expense_report', 'posted')
  RETURNING id INTO v_entry_id;

  -- One expense line per account, so a report may mix e.g. 4531 (foreign
  -- services) and 5420 (domestic software) and each lands where it belongs.
  FOR v_acct IN
    SELECT COALESCE(NULLIF(account_code, ''), p_expense_account) AS code,
           SUM(amount_cents - COALESCE(vat_cents, 0)) AS net_cents
    FROM public.expenses
    WHERE report_id = p_report_id
    GROUP BY COALESCE(NULLIF(account_code, ''), p_expense_account)
  LOOP
    IF v_acct.net_cents <> 0 THEN
      INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
      VALUES (v_entry_id, v_acct.code, v_acct.net_cents, 0, 'Expense (net)');
    END IF;
  END LOOP;

  INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES (v_entry_id, p_liability_account, 0, v_total_cents, 'Liability to employee');

  IF v_vat_cents <> 0 THEN
    INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
    VALUES (v_entry_id, p_vat_account, v_vat_cents, 0, 'Input VAT');
  END IF;

  -- Reverse charge: the buyer books both legs. Cash-neutral, but each must be
  -- reported — output in box 30/31/32, input in box 48.
  SELECT COALESCE(NULLIF(value #>> '{}', ''), value ->> 'id')
    INTO v_locale
    FROM public.site_settings WHERE key = 'accounting_locale' LIMIT 1;

  SELECT account_code INTO v_rc_input
    FROM public.account_roles
   WHERE locale = v_locale AND role = 'vat_input_reverse';

  FOR v_rc IN
    SELECT reverse_charge_rate AS rate,
           SUM(amount_cents - COALESCE(vat_cents, 0)) AS net_cents
    FROM public.expenses
    WHERE report_id = p_report_id
      AND reverse_charge_rate IS NOT NULL
    GROUP BY reverse_charge_rate
  LOOP
    v_rc_output := NULL;
    SELECT account_code INTO v_rc_output
      FROM public.account_roles
     WHERE locale = v_locale
       AND role = 'vat_output_reverse_' || ROUND(v_rc.rate * 100)::int::text;

    IF v_rc_output IS NULL OR v_rc_input IS NULL THEN
      v_rc_skipped := v_rc_skipped || jsonb_build_object(
        'rate', v_rc.rate,
        'net_cents', v_rc.net_cents,
        'reason', 'no account role vat_output_reverse_' || ROUND(v_rc.rate * 100)::int::text
                  || ' / vat_input_reverse for locale ' || COALESCE(v_locale, '(none)')
      );
      CONTINUE;
    END IF;

    v_rc_vat := ROUND(v_rc.net_cents * v_rc.rate);

    INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
    VALUES
      (v_entry_id, v_rc_input,  v_rc_vat, 0, 'Reverse charge input VAT'),
      (v_entry_id, v_rc_output, 0, v_rc_vat, 'Reverse charge output VAT');

    v_rc_total := v_rc_total + v_rc_vat;
  END LOOP;

  UPDATE public.expense_reports
  SET status = 'booked', journal_entry_id = v_entry_id
  WHERE id = p_report_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_id', p_report_id,
    'journal_entry_id', v_entry_id,
    'total_cents', v_total_cents,
    'reverse_charge_vat_cents', v_rc_total,
    'reverse_charge_skipped', v_rc_skipped
  );
END;
$function$;
