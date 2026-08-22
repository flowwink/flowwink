-- ============================================================================
-- A country is a CHOICE, not a default — get Swedish BAS out of the chain.
--
-- THE FINDING. Every FlowWink install in the world was born with 26 Swedish
-- accounts in chart_of_accounts, planted by four migrations that each had a
-- local reason and no country question:
--
--   20260706001101  1210, 2090, 2641, 7970        repair for posted lines on dev
--   20260708130001  7385                          payroll benefit cost account
--   20260726090000  2614/2615/2624/2625/2634/2635/2645   reverse-charge VAT
--   20260726140000  4515-4518, 4531-4538, 4545-4547      SKV value boxes
--
-- (4534 was dropped again by 20260810095345 when it turned out to be unused —
-- 27 planted, 26 surviving. That file is also the shape this one copies: delete
-- only what nothing has posted to.)
--
-- WHY IT MATTERS. The documented invariant is empty-until-chosen: with no
-- locale activated, bookkeeping must refuse LOUDLY so the operator picks a
-- standard. src/hooks/useTenantLocalePack.ts says so in as many words ("a
-- German instance must not wake up with 263 Swedish accounts because nobody had
-- picked yet") and account_for() enforces it. But import_accounting_standard —
-- the one supported way to LOAD a standard, with provenance and a sha256 gate —
-- gates on how many accounts the locale already has. On a fresh install it
-- answered:
--
--   "locale se-bas2024 already has 26 accounts. Pass replace=true to update it"
--
-- So the sanctioned path refused, and the reason it refused was 26 rows nobody
-- asked for. A half-configured chart is worse than an empty one: an empty chart
-- fails in a way that tells you what to do.
--
-- NONE of the 26 is an engine dependency. chart_of_accounts has no foreign key
-- pointing at it; journal_entry_lines.account_code is text. Every engine
-- reference is either a hardcoded Swedish code checked against POSTED LINES
-- (prepare_vat_return sums journal_entry_lines by code and never joins the
-- chart; approve_payroll_run posts to '7385'/'7399' as literals — and '7399'
-- was never seeded by anything, which is the proof that these rows are
-- reference data rather than a dependency) or a role lookup through
-- account_roles, which on a fresh install already points at seventeen codes the
-- chart does not contain. The 26 were accreted repairs, not a coherent set.
--
-- WHAT THIS FILE DOES. Existing instances are cleaned only where it is
-- provably safe:
--
--   * an instance that has ACTIVATED se-bas2024 keeps everything, untouched —
--     it is a Swedish instance and these are its accounts;
--   * on every other instance, a planted row is removed only if nothing
--     references the code anywhere: no journal line, no opening balance, no
--     budget, no expense, no template line, no vendor default. The reference
--     scan is discovered from the catalog, so a table added later is protected
--     without editing this file.
--
-- The four seeding migrations are edited in place to carry the same guard
-- (activated se-bas2024, or the books already name the code). Editing applied
-- migrations is safe because the end state of every instance that already ran
-- them is unchanged — the rows are already there and, on a Swedish instance,
-- the guard is true anyway. What changes is only what a FRESH chain produces:
-- nothing. Same pattern as the idempotency transformation of 2026-08-22.
--
-- WHAT IS DELIBERATELY LEFT. account_roles, account_tax_boxes and
-- account_statement_sections still carry se-bas2024 rows from the chain. They
-- are locale-KEYED maps, inert until a locale is activated — account_for()
-- refuses on activation, not on their contents — and an existing Swedish
-- instance depends on them. Lifting those into the locale pack is the next
-- step, not this one. They are excluded from the reference scan below for
-- exactly that reason: they are the pack's own map, not evidence of use.
--
-- Re-runnable: conditional DELETE, no DDL.
-- ============================================================================

DO $cleanup$
DECLARE
  -- The 27 codes the migration chain plants. Nothing outside this list is ever
  -- touched, so an account an operator created by hand is safe by construction.
  v_planted CONSTANT text[] := ARRAY[
    '1210','2090','2641','7970',                                  -- 20260706001101
    '7385',                                                       -- 20260708130001
    '2614','2615','2624','2625','2634','2635','2645',             -- 20260726090000
    '4515','4516','4517','4518',
    '4531','4532','4533','4534','4535','4536','4537','4538',
    '4545','4546','4547'                                          -- 20260726140000
  ];
  v_used    text[] := ARRAY[]::text[];
  v_codes   text[];
  v_removed int;
  v_left    int;
  r         RECORD;
BEGIN
  -- ── 0. A chosen market keeps its chart ────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.site_settings s
     WHERE s.key = 'accounting_locale'
       AND COALESCE(s.value ->> 'id', NULLIF(s.value #>> '{}', '')) = 'se-bas2024'
  ) THEN
    RAISE NOTICE '[locale] se-bas2024 is the activated market — chart left untouched.';
    RETURN;
  END IF;

  -- A row we cannot READ is not a row that says "no market". site_settings
  -- stores this value in two shapes — a bare JSON string and { "id": … } — and
  -- an unrecognised third shape must abstain rather than delete. (Note for the
  -- next reader: the widespread idiom COALESCE(NULLIF(value #>> '{}', ''),
  -- value ->> 'id') gets this backwards — on the object shape #>> '{}' returns
  -- the whole '{"id": "se-bas2024"}' text, which is non-empty, so the ->> 'id'
  -- arm never runs. The order is flipped here.)
  IF EXISTS (
    SELECT 1 FROM public.site_settings s
     WHERE s.key = 'accounting_locale'
       AND COALESCE(s.value ->> 'id', NULLIF(s.value #>> '{}', '')) !~ '^[a-z]{2,4}-[a-z0-9]+$'
  ) THEN
    RAISE NOTICE '[locale] accounting_locale is set but does not read as a pack id — abstaining.';
    RETURN;
  END IF;

  -- ── 1. Which codes does this instance actually reference? ─────────────────
  -- Discovered from the catalog rather than listed, so the protection survives
  -- new tables. Every base-table text column whose name ends in account_code
  -- counts as use: journal lines, opening balances, budgets, expenses, vendor
  -- and journal defaults, reconciliation suggestions, tax codes, petty cash,
  -- analytic lines, corrections.
  FOR r IN
    SELECT c.table_name, c.column_name
      FROM information_schema.columns c
      JOIN information_schema.tables t
        ON t.table_schema = c.table_schema
       AND t.table_name   = c.table_name
       AND t.table_type   = 'BASE TABLE'
     WHERE c.table_schema = 'public'
       AND c.column_name ~ 'account_code$'
       AND c.data_type IN ('text', 'character varying')
       -- The locale pack's own maps. Their rows were planted by the same chain
       -- and cover every code in v_planted; counting them as "use" would make
       -- this migration a no-op that reports success.
       AND c.table_name NOT IN (
         'chart_of_accounts', 'account_roles', 'account_tax_boxes',
         'account_statement_sections'
       )
  LOOP
    EXECUTE format(
      'SELECT COALESCE(array_agg(DISTINCT %I::text), ARRAY[]::text[]) FROM public.%I WHERE %I IS NOT NULL',
      r.column_name, r.table_name, r.column_name
    ) INTO v_codes;
    v_used := v_used || v_codes;
  END LOOP;

  -- Template lines live in JSONB, so the column scan cannot see them.
  IF to_regclass('public.accounting_templates') IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT e ->> 'account_code'), ARRAY[]::text[])
      INTO v_codes
      FROM public.accounting_templates t
      CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(t.template_lines) = 'array'
             THEN t.template_lines ELSE '[]'::jsonb END) AS e
     WHERE NULLIF(e ->> 'account_code', '') IS NOT NULL;
    v_used := v_used || v_codes;
  END IF;

  -- ── 2. Remove what this instance never chose and never used ───────────────
  WITH gone AS (
    DELETE FROM public.chart_of_accounts c
     WHERE c.locale = 'se-bas2024'
       AND c.account_code = ANY (v_planted)
       AND NOT (c.account_code = ANY (v_used))
    RETURNING 1
  )
  SELECT count(*) INTO v_removed FROM gone;

  SELECT count(*) INTO v_left FROM public.chart_of_accounts;

  RAISE NOTICE '[locale] se-bas2024 is not the market this instance chose — removed % unused account(s) planted by the migration chain; % chart row(s) remain.',
    v_removed, v_left;

  IF v_left = 0 THEN
    RAISE NOTICE '[locale] chart is empty, as an unchosen instance should be: account_for() refuses and import_accounting_standard can now load a full standard without replace=true.';
  END IF;
END $cleanup$;
