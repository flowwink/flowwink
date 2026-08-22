-- ═══════════════════════════════════════════════════════════════════════════
-- En vakt som bara SER UT som en vakt
--
-- Två fynd ur samma familj: en sats som läser som ett skydd, men som inte
-- skyddar någonting — och ett skydd som finns i repot men aldrig nådde
-- produktionsinstansen.
--
-- ── FYND 1: "Daily Briefing" föds duplicerad ──────────────────────────────
-- 20260624225254 seedar automationen med `ON CONFLICT DO NOTHING` mot
-- public.agent_automations. Tabellen har PRIMARY KEY ("id") med
-- gen_random_uuid()-default och INGEN unik nyckel på `name`. En naken
-- ON CONFLICT kan bara utlösas av en faktisk unik-överträdelse; eftersom
-- varje INSERT föder ett nytt uuid finns ingen konflikt att fånga. Satsen är
-- en NO-OP som vakt. Beviset är asymmetrin mot de tre syskonautomationerna
-- (Quote Expiry Reminders, Webinar Reminders, Notify approvers in cowork
-- chat) som alla använder `WHERE NOT EXISTS` och förblir enkla:
--
--   -- lokal fresh DB, samma migrationskedja körd tre gånger i BEGIN/ROLLBACK
--   Daily Briefing                  | 3
--   Notify approvers in cowork chat | 1
--   Quote Expiry Reminders          | 1
--   Webinar Reminders               | 1
--
-- VALT MÖNSTER: `NOT EXISTS`, INTE ett unikt index på `name`. Motivering:
--   * `name` är inte en deklarerad nyckel — den är fritext. Både admin-UI:t
--     (useAutomations) och agentytan (manage_automation → agent-execute
--     'automations'.create) samt NewsletterPage skapar automationer med
--     användarvalda namn. Ett globalt UNIQUE skulle förvandla "två
--     automationer som råkar heta likadant" till ett hårt insert-fel på ytor
--     som saknar dedup-UX.
--   * Ett unikt index är dessutom fail-closed vid DDL: på varje instans som
--     REDAN bär dubbletter skulle CREATE UNIQUE INDEX få hela migrationen att
--     smälla. Att låsa deployen för en seed-bugg är värre än buggen.
--   * Det finns ingen ren diskriminator för "plattformsseedad" att göra ett
--     PARTIELLT unikt index på: executor='platform' är också default för
--     användarskapade rader (useAutomations).
--   * Syskonen använder redan NOT EXISTS. Fixen ska ta bort asymmetrin, inte
--     införa ett fjärde mönster.
-- Källfilen 20260624225254 är rättad i samma commit (samma hus-praxis som
-- scripts/make-migrations-idempotent.ts) — den här migrationen städar de
-- instanser som redan hunnit få dubbletter.
--
-- ── FYND 2: document_counters har RLS AVSTÄNGT på optic ───────────────────
-- 20260808153845 slår på RLS + policy "Staff can view document counters".
-- Fresh install har rätt tillstånd (relrowsecurity = t, 1 policy). optic har
-- relrowsecurity = f och NOLL policies trots att 20260808153845 STÅR i
-- ledgern — en spökrad: registrerad men aldrig utförd. Namn-i-liggaren är
-- svagt bevis; objektet är det starka (jfr project_platform_config_must_be_seeded).
-- Effekt: `authenticated` har SELECT/INSERT/UPDATE/DELETE på tabellen utan
-- någon radgrind alls — varje inloggad användare oavsett roll kan skruva på
-- dokumentnumreringen. Fyndet noterades i anon-svepet (20260822010000, FYND 7)
-- och lämnades då som eget spår. Det här är det spåret.
--
-- ANROPARE (kontrollerat före påslag): enda funktionen som skriver till
-- document_counters är public.next_document_number(text,text) — SECURITY
-- DEFINER, ägd av postgres, alltså RLS-passerande. Edge functions går via
-- service_role som också passerar. Ingen klientyta rör tabellen direkt
-- (src/ använder uteslutande .rpc('next_document_number', …)). Att slå på RLS
-- låser därför inte ute någon legitim väg.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1) Städa befintliga Daily Briefing-dubbletter (idempotent) ────────────
-- Behåller ÄLDSTA raden per namn och tar bort resten — men ENDAST när
-- kopiorna är identiska i beteendemässig konfiguration (trigger_type,
-- trigger_config, skill_name, skill_arguments, executor). Skiljer de sig åt
-- är det inte längre en seed-dubblett utan två olika automationer som råkar
-- dela namn: då rörs de inte, och namnet rapporteras i stället.
--
-- Överlevaren ärver körhistoriken (MAX(last_triggered_at), SUM(run_count)) så
-- att kadensvakterna inte tror att automationen aldrig kört och eldar av den
-- direkt efter städningen.
DO $idem$
DECLARE
  r record;
  v_keep uuid;
  v_last timestamptz;
  v_runs integer;
  v_removed integer := 0;
BEGIN
  FOR r IN
    SELECT name, count(*) AS n
    FROM public.agent_automations
    GROUP BY name
    HAVING count(*) > 1
  LOOP
    -- Divergerande konfiguration → rapportera, gissa inte.
    IF (
      SELECT count(*) FROM (
        SELECT DISTINCT trigger_type, trigger_config, skill_name,
                        skill_arguments, executor
        FROM public.agent_automations WHERE name = r.name
      ) d
    ) > 1 THEN
      RAISE NOTICE
        'agent_automations: % rader heter "%" men skiljer sig i konfiguration — lämnas orörda, kräver mänskligt beslut.',
        r.n, r.name;
      CONTINUE;
    END IF;

    SELECT id INTO v_keep
    FROM public.agent_automations
    WHERE name = r.name
    ORDER BY created_at, id
    LIMIT 1;

    SELECT max(last_triggered_at), sum(run_count)
      INTO v_last, v_runs
    FROM public.agent_automations
    WHERE name = r.name;

    DELETE FROM public.agent_automations
    WHERE name = r.name AND id <> v_keep;
    GET DIAGNOSTICS v_removed = ROW_COUNT;

    UPDATE public.agent_automations
    SET last_triggered_at = v_last,
        run_count         = COALESCE(v_runs, run_count),
        updated_at        = now()
    WHERE id = v_keep;

    RAISE NOTICE 'agent_automations: tog bort % identiska dubbletter av "%".',
      v_removed, r.name;
  END LOOP;
END
$idem$;

-- ── 2) document_counters: samma sluttillstånd som en fresh install ────────
-- Fresh install (verifierat lokalt):
--   relrowsecurity = t
--   POLICY "Staff can view document counters" FOR SELECT TO authenticated
--     USING (has_role(auth.uid(), 'admin'::app_role))
ALTER TABLE public.document_counters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view document counters" ON public.document_counters;
CREATE POLICY "Staff can view document counters" ON public.document_counters
  FOR SELECT TO authenticated USING (has_role(auth.uid(), 'admin'::app_role));

-- Grants som djupförsvar: RLS är radgrinden, granten är tabellgrinden. Ingen
-- legitim väg skriver som `authenticated` (se ANROPARE ovan) — bara
-- SECURITY DEFINER-numreraren och service_role, som båda passerar RLS.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.document_counters FROM authenticated;
REVOKE ALL ON public.document_counters FROM anon;
GRANT SELECT ON public.document_counters TO authenticated;
GRANT ALL ON public.document_counters TO service_role;

NOTIFY pgrst, 'reload schema';
