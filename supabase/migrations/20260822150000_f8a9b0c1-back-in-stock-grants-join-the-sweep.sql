-- back_in_stock_requests ansluter till anon-svepet — undantaget stängs.
--
-- 20260822010000 krympte anons tabellyta över hela schemat men UNDANTOG
-- uttryckligen back_in_stock_requests: en parallell session ägde tabellen
-- (upsert-buggen, PR #244). Undantaget var rätt då — två sessioner som skriver
-- samma tabell är värre än ett kvarvarande grant. Nu har #244 landat, tabellen
-- är åter i en hand, och undantaget ska inte överleva sin anledning.
--
-- Mätt live på optic FÖRE denna migration:
--   anon-grants: INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
--   anon SELECT → 0 rader (RLS håller: ingen anon-läspolicy finns)
--   anon TRUNCATE → "TRUNCATE TABLE" ... LYCKADES.
--
-- Det sista är hålet. TRUNCATE styrs INTE av radpolicies — har man granten
-- tömmer man tabellen oavsett vad varje policy i schemat säger. En anonym
-- besökare med den publika nyckeln kunde radera hela bevakningskön.
-- SELECT/UPDATE/DELETE är död yta (grant utan policy) och dras in av samma
-- skäl som i huvudsvepet: en ensam slarvig policy ska inte kunna öppna en
-- dörr som granten redan lämnat på glänt.
--
-- BEHÅLLS: INSERT. Policyn "Anyone can request back in stock notifications"
-- är en avsedd publik skrivyta (samma klass som newsletter_subscribers), och
-- frontend behåller den vägen som fallback för instanser som ännu inte fått
-- request_back_in_stock — fleeten kör flera schemaversioner samtidigt med
-- avsikt. Den skarpa vägen är RPC:n; detta är bara kvarhållen bakåtkompat.

DO $$
DECLARE
  v_verb text;
BEGIN
  IF to_regclass('public.back_in_stock_requests') IS NULL THEN
    RAISE NOTICE 'back_in_stock_requests saknas på denna instans — hoppar över';
    RETURN;
  END IF;

  -- Död yta från anon: läsning/ändring/radering har ingen policy som anon kan
  -- uppfylla, så granten fyller ingen funktion — bara risk.
  FOREACH v_verb IN ARRAY ARRAY['SELECT','UPDATE','DELETE'] LOOP
    EXECUTE format('REVOKE %s ON TABLE public.back_in_stock_requests FROM anon', v_verb);
  END LOOP;

  -- TRUNCATE från BÅDA rollerna, precis som huvudsvepet gjorde för resten av
  -- schemat. Ingen frontend eller edge-funktion truncatear någonting.
  EXECUTE 'REVOKE TRUNCATE ON TABLE public.back_in_stock_requests FROM anon';
  EXECUTE 'REVOKE TRUNCATE ON TABLE public.back_in_stock_requests FROM authenticated';

  RAISE NOTICE 'back_in_stock_requests: anon-ytan krympt (INSERT behållen)';
END $$;

-- ── LACKMUS ────────────────────────────────────────────────────────────────
--   SET ROLE anon; TRUNCATE public.back_in_stock_requests;  → permission denied
--   SET ROLE anon; SELECT * FROM public.back_in_stock_requests; → permission denied
--   SET ROLE anon; SELECT public.request_back_in_stock('<produkt>','a@b.se');
--       → fungerar (SECURITY DEFINER-vägen är opåverkad)
