-- === 20260810230000_the-closing-balance-becomes-the-opening-balance.sql ===
-- ============================================================================
-- UB blir IB. The opening balance is derived, never stored twice.
--
-- The balance sheet read `opening_balances` for the SELECTED year, so a year
-- with no stored row got no opening balance at all. On liteit — 2022 through
-- 2026 bookkept and reconciled against three annual reports — only 2026 had
-- rows. 2023, 2024 and 2025 opened at zero.
--
-- But the missing rows were the symptom. The defect is that an opening balance
-- was STORED per year, which puts the same number in two places: 2025's closing
-- balance and 2026's opening balance. Two records of one fact drift, and these
-- already had:
--
--     derived from the ledger        stored as opening balance 2026
--     151 983 on 1351               151 983 on 1350
--    -166 549,84 on 2893           -166 550 on 2393
--
-- Same money, different accounts — and 2393 is a long-term liability while 2893
-- is short-term, so the two records disagreed about the SHAPE of the balance
-- sheet, not merely about ören. Nothing could detect it, because the two were
-- never compared. (Magnus confirmed 1351 and 2893 — the ledger — are correct.)
--
-- The rule that replaces it:
--
--     opening balance of year Y = everything posted before Y-01-01
--
-- No storage, no copy, no drift. Correct a prior year and every later year's
-- opening balance follows automatically, which is precisely what a carry-forward
-- means.
--
-- `opening_balances` keeps exactly one job: the BRIDGE into the system — the
-- first year, where the numbers come from somewhere else (a Bokio SIE file, a
-- previous accountant). After that the ledger is the only source. On liteit the
-- bridge is already a verification (IB-2022, nine lines from the SIE), so the
-- rule needs no special case there at all: the bridge is simply the oldest
-- entries.
--
-- Result accounts do not carry forward — they reset each year and the net goes
-- to equity. Which accounts those are is read from `account_type` in the chart,
-- NOT inferred from the leading digit: 2641 is an asset in class 2, and class 8
-- holds income, revenue and expense side by side. Same ruling as the 8999
-- result-carrier incident — classification belongs to the chart of accounts.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.opening_balances_for_year(p_year integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_start date;
  v_bridge_year int;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL AND coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Sign in to read opening balances';
  END IF;
  IF p_year IS NULL THEN
    RAISE EXCEPTION 'p_year is required (the fiscal year whose OPENING balance you want)';
  END IF;

  v_start := make_date(p_year, 1, 1);

  -- The bridge is the earliest year anyone entered opening balances for. Later
  -- years are legacy copies of a carry-forward and are deliberately ignored —
  -- they are the drift this function exists to end.
  SELECT min(fiscal_year) INTO v_bridge_year FROM public.opening_balances;

  WITH bridge AS (
    SELECT ob.account_code,
           ob.account_name,
           sum(CASE WHEN ob.balance_type = 'credit' THEN -ob.amount_cents ELSE ob.amount_cents END)::bigint AS net_cents
      FROM public.opening_balances ob
     WHERE v_bridge_year IS NOT NULL
       AND ob.fiscal_year = v_bridge_year
       -- A bridge dated after the year being asked about has not happened yet.
       AND p_year >= v_bridge_year
     GROUP BY 1, 2
  ),
  movements AS (
    SELECT l.account_code,
           max(l.account_name)                            AS account_name,
           sum(l.debit_cents - l.credit_cents)::bigint    AS net_cents
      FROM public.journal_entry_lines l
      JOIN public.journal_entries je ON je.id = l.journal_entry_id
     WHERE je.status = 'posted'
       AND je.entry_date < v_start
       -- Only what the bridge covers; entries before the bridge year would be
       -- counted twice, since the bridge already states the position then.
       AND (v_bridge_year IS NULL OR je.entry_date >= make_date(v_bridge_year, 1, 1))
     GROUP BY 1
  ),
  combined AS (
    SELECT coalesce(b.account_code, m.account_code)                       AS account_code,
           coalesce(b.account_name, m.account_name)                       AS account_name,
           coalesce(b.net_cents, 0) + coalesce(m.net_cents, 0)            AS net_cents
      FROM bridge b FULL OUTER JOIN movements m ON m.account_code = b.account_code
  )
  SELECT jsonb_agg(jsonb_build_object(
           'account_code', c.account_code,
           'account_name', coalesce(c.account_name, coa.account_name),
           -- Signed against the debit side. The caller applies normal_balance.
           'net_cents',    c.net_cents
         ) ORDER BY c.account_code)
    INTO v_rows
    FROM combined c
    JOIN public.chart_of_accounts coa ON coa.account_code = c.account_code
   WHERE c.net_cents <> 0
     -- Balance-sheet accounts only. A result account opens every year at zero.
     AND coa.account_type IN ('asset', 'equity', 'liability');

  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMENT ON FUNCTION public.opening_balances_for_year(integer) IS
  'The opening balance of each balance-sheet account at the start of p_year, derived: the bridge (earliest year in opening_balances, if any) plus every posted entry after it and before p_year. net_cents is signed against the debit side — apply normal_balance to display. Result accounts are excluded because they open at zero. Storing an opening balance per year is what this replaces: it puts one number in two places and they drift.';

GRANT EXECUTE ON FUNCTION public.opening_balances_for_year(integer) TO authenticated, service_role;

-- ── Does this instance still hold a stored carry-forward? ───────────────────
DO $$
DECLARE
  v_years int;
  v_bridge int;
  v_list text;
BEGIN
  SELECT count(DISTINCT fiscal_year), min(fiscal_year) INTO v_years, v_bridge
    FROM public.opening_balances;

  IF v_years > 1 THEN
    SELECT string_agg(DISTINCT fiscal_year::text, ', ' ORDER BY fiscal_year::text)
      INTO v_list FROM public.opening_balances WHERE fiscal_year <> v_bridge;
    RAISE WARNING 'Opening balances: % is the bridge year, but rows also exist for %. Those are stored carry-forwards — they are IGNORED from now on and the ledger decides. Compare them before deleting: a disagreement is a real bookkeeping difference, not a formatting one.',
      v_bridge, v_list;
  ELSIF v_years = 1 THEN
    RAISE NOTICE 'Opening balances: one bridge year (%). Every later year now carries forward from the ledger.', v_bridge;
  ELSE
    RAISE NOTICE 'Opening balances: none stored — the bridge is a verification in the ledger, and carry-forward is derived.';
  END IF;
END $$;


-- === 20260811020000_handbook-joins-the-knowledge-index.sql ===
-- ============================================================================
-- The handbook joins the knowledge index.
--
-- handbook_chapters — the customer's OWN handbook, the Handbook module in the
-- admin nav — was never indexed. The reindex trigger sat on documents,
-- kb_articles, pages and wiki_pages, but not here. A team writing its handbook
-- produced content no retrieval surface could see: not FlowWork, not FlowPilot,
-- not search_knowledge.
--
-- (Not to be confused with docs_pages, which is FlowWink's repo documentation
-- synced per instance. Confusing the two briefly exposed vendor architecture
-- notes in a customer chat on 2026-08-11. This migration indexes the CUSTOMER's
-- book.)
--
-- queue_knowledge_reindex() is generic over TG_TABLE_NAME, so joining the
-- index is exactly one trigger, plus a seed of whatever already exists.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_knowledge_reindex ON public.handbook_chapters;
CREATE TRIGGER trg_knowledge_reindex
  AFTER INSERT OR UPDATE OR DELETE ON public.handbook_chapters
  FOR EACH ROW EXECUTE FUNCTION public.queue_knowledge_reindex();

-- Queue every existing chapter once, so instances that already hold content
-- get indexed on the next sweep instead of waiting for an edit.
INSERT INTO public.knowledge_index_queue (source_table, entity_id, op)
SELECT 'handbook_chapters', id::text, 'upsert' FROM public.handbook_chapters
ON CONFLICT (source_table, entity_id)
  DO UPDATE SET op = 'upsert', queued_at = now(), attempts = 0, last_error = NULL;

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.handbook_chapters;
  IF v_n > 0 THEN
    RAISE NOTICE 'Handbook: % existing chapter(s) queued for indexing — searchable after the next indexer sweep (≤5 min).', v_n;
  ELSE
    RAISE NOTICE 'Handbook: empty today, but every chapter written from now on is indexed as it is saved.';
  END IF;
END $$;


-- === 20260811021000_the-extractor-says-success-the-indexer-heard-completed.sql ===
-- ============================================================================
-- The extractor says 'success'; the indexer listened for 'completed'.
--
-- Every writer of documents.extraction_status on this platform writes
-- 'success' (upload_document, extract-pdf-text). The knowledge indexer's
-- documents case required 'completed' — a literal no writer has ever
-- produced. Result: NOT ONE document has ever been indexed, including fully
-- extracted ones with content_md in place. The Documents source appeared in
-- every chat's source picker and always returned nothing.
--
-- Same near-miss-literal class as the VAT coverage `<> 'void'` filter
-- (2026-08-09): a filter that never matches fails silently, and silence reads
-- as "no documents" rather than "broken check".
--
-- The code fix lives in _shared/retrieval/indexer.ts (accepts the literal
-- actually written). This migration re-queues every extracted document so the
-- next indexer sweep (≤5 min) finally chunks them.
-- ============================================================================

INSERT INTO public.knowledge_index_queue (source_table, entity_id, op)
SELECT 'documents', id::text, 'upsert'
  FROM public.documents
 WHERE extraction_status IN ('success', 'completed')
   AND coalesce(content_md, '') <> ''
ON CONFLICT (source_table, entity_id)
  DO UPDATE SET op = 'upsert', queued_at = now(), attempts = 0, last_error = NULL;

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.documents
   WHERE extraction_status IN ('success', 'completed') AND coalesce(content_md, '') <> '';
  RAISE NOTICE 'Documents: % extracted document(s) re-queued for indexing. They were never chunked — the indexer was listening for a status no writer produces.', v_n;
END $$;


-- === 20260811120000_the-activity-log-knows-all-its-actors.sql ===
-- ============================================================================
-- The activity log must know every actor that acts.
--
-- agent_activity.agent is the enum agent_type — and it stopped growing when
-- the platform didn't: 'admin_ui' (the B1a callSkill rail) and 'flowwork'
-- (the employee dispatch surface) were never added. Every logActivity insert
-- for those actors has failed silently ever since: the skill executed, the
-- evidence did not land.
--
-- On a platform whose objectives close on EVIDENCE from agent_activity —
-- never on prose — a caller whose actions cannot be logged is a caller whose
-- work cannot be proven. The monitors watching for FlowWork's first live
-- calls were blind by construction.
--
-- ALTER TYPE ... ADD VALUE cannot run inside a DO block; plain statements,
-- idempotent via IF NOT EXISTS.
-- ============================================================================

ALTER TYPE public.agent_type ADD VALUE IF NOT EXISTS 'admin_ui';
ALTER TYPE public.agent_type ADD VALUE IF NOT EXISTS 'flowwork';


-- === 20260811140000_first-user-on-a-virgin-instance-claims-admin.sql ===
-- ============================================================================
-- The first account on a virgin instance claims admin — the self-hosted way.
--
-- Ghost, Gitea, Grafana, Plausible: the operator deploys their own instance
-- and the first person to reach the login screen becomes the admin. FlowWink
-- couldn't do that — handle_new_user() fails closed to 'customer', so a brand
-- new self-hosted instance was born with NO admin and no CLI-free way to make
-- one (you had to set signup_type metadata by hand or run SQL).
--
-- This adds the missing branch, gated on the only thing that makes it safe:
--
--     grant admin to a new signup ONLY WHILE zero admins exist.
--
-- The window is exactly "a virgin instance nobody administers yet", and it
-- bolts shut the instant the first admin row lands. This does NOT reopen the
-- hole the fail-closed migration (20260726190000) closed — that hole was
-- "empty metadata ALWAYS becomes admin", reachable on any instance at any
-- time. This branch is reachable only when the admin count is zero, which for
-- every provisioned instance it already is not: all five fleet instances have
-- an admin today, so their behaviour is unchanged. Only a fresh birth sees it.
--
-- pg_advisory_xact_lock serialises the check-and-grant so two near-simultaneous
-- first signups cannot both claim admin — the second sees count = 1 and falls
-- through to the normal fail-closed decision.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  signup_type text;
  v_admin_count integer;
BEGIN
  -- Fail CLOSED. Absent or unrecognised metadata must never imply privilege.
  signup_type := COALESCE(NEW.raw_user_meta_data ->> 'signup_type', 'customer');

  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email)
  )
  ON CONFLICT (id) DO NOTHING;

  -- Serialise the virgin-instance check so a race can't mint two admins.
  PERFORM pg_advisory_xact_lock(hashtext('handle_new_user:first_admin'));
  SELECT count(*) INTO v_admin_count FROM public.user_roles WHERE role = 'admin';

  IF v_admin_count = 0 THEN
    -- Virgin instance: the first account is the operator. Claim admin, and the
    -- window closes here. Self-hosted bootstrap — safe because it is gated on
    -- there being no admin at all, not on being "first" in general.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'admin')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSIF signup_type = 'admin' THEN
    -- Reached only when a provisioning path asks for it by name.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'admin')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSIF signup_type = 'employee' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'writer')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    -- 'customer', anything unrecognised, and anything absent.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'customer')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

DO $$
DECLARE v_admins integer;
BEGIN
  SELECT count(*) INTO v_admins FROM public.user_roles WHERE role = 'admin';
  IF v_admins = 0 THEN
    RAISE NOTICE 'First-admin bootstrap ACTIVE: this instance has no admin — the next signup claims it.';
  ELSE
    RAISE NOTICE 'First-admin bootstrap dormant: % admin(s) already exist, so the next signup follows the normal fail-closed rules.', v_admins;
  END IF;
END $$;