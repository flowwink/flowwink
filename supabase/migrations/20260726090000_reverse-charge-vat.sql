-- Reverse-charge (omvänd skattskyldighet) VAT on expense reports.
--
-- FOUND 2026-07-25 on real liteit data: a Kilo Code invoice (US supplier, paid
-- by card) booked through the expense flow produced
--     5420 debit 191,47 / 1930 credit 191,47 / 2645 0,00
-- i.e. NET, with no reverse-charge VAT pair. For a Swedish company buying
-- foreign SaaS that understates BOTH VAT return box 30 (utgående moms on
-- reverse charge) and box 48 (ingående moms) — the two net to zero in cash, but
-- each must still be REPORTED. Box 49 = (10+11+12+30+31+32) − 48.
--
-- Worse: 13 of the 14 accounts the SE VAT pack's boxes 30/31/32 reference did
-- not exist in chart_of_accounts at all, so those boxes could only ever read
-- zero. The declaration was structurally incapable of being right.
--
-- Idempotent + forward-dated (Lovable's migrate runner silently SKIPS a
-- migration whose timestamp is below its ledger HEAD).

-- ─── 1. Declare reverse charge as DATA, never infer it ──────────────────────
--
-- Law 1: no hardcoded intent detection. We do NOT guess "foreign supplier"
-- from currency <> 'SEK' or from the vendor string — a USD invoice can carry
-- Swedish VAT, and an EUR one may not be reverse-charged at all. The caller
-- (human or agent) declares it. NULL = not reverse charge, which is what every
-- existing row correctly becomes.
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS reverse_charge_rate numeric;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.expenses'::regclass
      AND conname = 'expenses_reverse_charge_rate_check'
  ) THEN
    ALTER TABLE public.expenses
      ADD CONSTRAINT expenses_reverse_charge_rate_check
      CHECK (reverse_charge_rate IS NULL OR (reverse_charge_rate > 0 AND reverse_charge_rate < 1));
  END IF;
END $$;

COMMENT ON COLUMN public.expenses.reverse_charge_rate IS
  'Reverse charge (omvänd skattskyldighet) VAT rate as a fraction, e.g. 0.25. '
  'NULL = not reverse charge. Set explicitly — never inferred from currency or vendor.';

-- ─── 2. The accounts the SE VAT boxes already point at ──────────────────────
-- Only the ones boxes 30/31/32 reference. `is_active=false` would hide them
-- from pickers; they are real postable accounts, so they are active.
-- REPLAY GUARD (2026-08-13): was `ON CONFLICT (account_code)`, which names the
-- unique constraint of THIS file's era. The locale work later replaced it with
-- UNIQUE (locale, account_code), so replaying this file onto a newer schema is
-- 42P10 (no matching constraint) — found when a lagging fork's deploy replayed
-- its pending tail. WHERE NOT EXISTS expresses the same idempotency without
-- naming any constraint, so it survives both schema generations.
INSERT INTO public.chart_of_accounts
  (account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
SELECT v.*
FROM (VALUES
  ('2614', 'Beräknad utgående moms på tjänsteförvärv från utlandet, 25%', 'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2615', 'Beräknad utgående moms på varuförvärv från utlandet, 25%',    'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2624', 'Beräknad utgående moms på tjänsteförvärv från utlandet, 12%', 'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2625', 'Beräknad utgående moms på varuförvärv från utlandet, 12%',    'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2634', 'Beräknad utgående moms på tjänsteförvärv från utlandet, 6%',  'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2635', 'Beräknad utgående moms på varuförvärv från utlandet, 6%',     'liability', 'skulder', 'credit', true, 'se-bas2024'),
  ('2645', 'Beräknad ingående moms på förvärv från utlandet',             'asset',     'tillgångar', 'debit',  true, 'se-bas2024')
) AS v(account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
WHERE NOT EXISTS (
  SELECT 1 FROM public.chart_of_accounts c
   WHERE c.account_code = v.account_code AND c.locale = v.locale
);

-- ─── 3. Roles, not account numbers ──────────────────────────────────────────
-- The engine must never branch on country. book_expense_report resolves these
-- through account_for(); a locale that does not model reverse charge simply has
-- no rows here, and the RPC then books nothing extra (see below).
INSERT INTO public.account_roles (locale, role, account_code)
VALUES
  ('se-bas2024', 'vat_input_reverse',     '2645'),
  ('se-bas2024', 'vat_output_reverse_25', '2614'),
  ('se-bas2024', 'vat_output_reverse_12', '2624'),
  ('se-bas2024', 'vat_output_reverse_6',  '2634')
ON CONFLICT (locale, role) DO NOTHING;

-- ─── 4. Book the pair ───────────────────────────────────────────────────────
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
  v_net_cents bigint;
  v_entry_id uuid;
  v_date date;
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

  v_net_cents := v_total_cents - v_vat_cents;
  v_date := COALESCE(p_entry_date, CURRENT_DATE);

  INSERT INTO public.journal_entries (entry_date, description, source, status)
  VALUES (v_date, 'Expense report ' || p_report_id::text, 'expense_report', 'posted')
  RETURNING id INTO v_entry_id;

  INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
  VALUES
    (v_entry_id, p_expense_account, v_net_cents, 0, 'Expense (net)'),
    (v_entry_id, p_liability_account, 0, v_total_cents, 'Liability to employee');

  -- Only post an input-VAT line when there IS input VAT. A reverse-charge
  -- purchase carries none (the supplier charged nothing), and a 0/0 line is
  -- noise in the voucher — doubly so next to the real 2645 leg booked below.
  IF v_vat_cents <> 0 THEN
    INSERT INTO public.journal_entry_lines (journal_entry_id, account_code, debit_cents, credit_cents, description)
    VALUES (v_entry_id, p_vat_account, v_vat_cents, 0, 'Input VAT');
  END IF;

  -- Reverse charge: the supplier charged no VAT, so the buyer books BOTH sides.
  -- Cash-neutral (the pair nets to zero) but each leg must be reported —
  -- output in VAT box 30/31/32, input in box 48. Grouped per declared rate so
  -- a report may mix 25% services and 6% goods.
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
    -- Role name carries the whole-percent rate: 0.25 → vat_output_reverse_25.
    v_rc_output := NULL;
    SELECT account_code INTO v_rc_output
      FROM public.account_roles
     WHERE locale = v_locale
       AND role = 'vat_output_reverse_' || ROUND(v_rc.rate * 100)::int::text;

    IF v_rc_output IS NULL OR v_rc_input IS NULL THEN
      -- Honest no-op: record WHY, never post to a guessed account. A locale that
      -- does not model reverse charge, or a rate with no role, lands here.
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

-- ─── 5. Make the VAT return able to SEE the pair ────────────────────────────
--
-- Booking the pair without this makes the declaration WORSE, not better: the
-- input leg (2645) was already counted, the output leg was not, so a
-- reverse-charge purchase produced a refund claim the company is not owed.
-- Proven live on sandbox before this fix: net_to_pay_sek −47,87 where the
-- correct answer is 0 (the pair nets out).
--
-- Two real bugs in the existing buckets, both from hardcoded account codes
-- that had drifted from the declarative box map in
-- src/lib/locale-packs/se/vat-return-2026.ts:
--   * reverse charge summed '2611' — which is *Utgående moms på försäljning
--     INOM Sverige, 25%*, an unrelated account. Reverse charge lives on
--     2614/2615 (+2624/2625, 2634/2635 for the reduced rates).
--   * the rate buckets read a single account each (2610/2620/2630), so ordinary
--     sales booked to 2611/2621/2631 — the normal case — were invisible.
--
-- Aligned to the pack's boxes 10/11/12, 30/31/32 and 48. NOTE the remaining
-- architectural debt: this list is still hardcoded SQL that must be kept in
-- sync with a TypeScript pack by hand. The right fix is to move the box map
-- into a table both sides read; tracked separately.
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
    -- Box 10 — output VAT 25% (2614/2615 deliberately excluded: they are box 30)
    COALESCE(SUM(CASE WHEN l.account_code IN ('2610','2611','2612','2613','2616','2617','2618','2619')
                      THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    -- Box 11 — output VAT 12%
    COALESCE(SUM(CASE WHEN l.account_code IN ('2620','2621','2622','2623','2626','2627','2628','2629')
                      THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    -- Box 12 — output VAT 6%
    COALESCE(SUM(CASE WHEN l.account_code IN ('2630','2631','2632','2633','2636','2637','2638','2639')
                      THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    -- Boxes 30/31/32 — reverse charge & EU acquisitions, all rates
    COALESCE(SUM(CASE WHEN l.account_code IN ('2614','2615','2624','2625','2634','2635')
                      THEN l.credit_cents - l.debit_cents ELSE 0 END), 0),
    -- Box 48 — deductible input VAT
    COALESCE(SUM(CASE WHEN l.account_code IN ('2640','2641','2642','2643','2644','2645','2646','2647','2648','2649')
                      THEN l.debit_cents - l.credit_cents ELSE 0 END), 0)
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
    'note', 'Box 10/11/12 = output VAT 25/12/6% (2610-2613, 2616-2619 etc). Box 30/31/32 = reverse charge and EU acquisitions (2614/2615, 2624/2625, 2634/2635). Box 48 = input VAT (2640-2649). Net = (10+11+12+30+31+32) - 48. Verify against the VAT control account before filing.'
  );
END;
$function$;
