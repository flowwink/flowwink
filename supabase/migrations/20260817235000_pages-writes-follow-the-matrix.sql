-- Svante-fynd 2026-08-17 (kväll): marketing-rollen har pages-modulen i
-- matrisen och ser hela editorn — men Spara ger röd toast, för pages-tabellens
-- skrivpolicies kräver writer/approver/admin-literaler. Samma klass som
-- 20260817220000 (KB + blogg följde matrisen) — pages-tabellen glömdes.
--
-- ADDITIVT: matrisvägen läggs BREDVID writer/approver-vägarna (permissive OR).
-- DELETE förblir admin — att radera en publicerad sida är en större handling
-- än att redigera den.

DO $$
BEGIN
  IF to_regclass('public.pages') IS NOT NULL THEN
    DROP POLICY IF EXISTS "pages module updates pages" ON public.pages;
    CREATE POLICY "pages module updates pages" ON public.pages
      FOR UPDATE USING (public.can_access_module(auth.uid(), 'pages'))
      WITH CHECK (public.can_access_module(auth.uid(), 'pages'));

    DROP POLICY IF EXISTS "pages module creates pages" ON public.pages;
    CREATE POLICY "pages module creates pages" ON public.pages
      FOR INSERT WITH CHECK (public.can_access_module(auth.uid(), 'pages'));
  END IF;

  -- Editorn skriver även sidversioner vid spara — samma matrisväg.
  IF to_regclass('public.page_versions') IS NOT NULL THEN
    DROP POLICY IF EXISTS "pages module writes page_versions" ON public.page_versions;
    CREATE POLICY "pages module writes page_versions" ON public.page_versions
      FOR ALL USING (public.can_access_module(auth.uid(), 'pages'))
      WITH CHECK (public.can_access_module(auth.uid(), 'pages'));
  END IF;
END $$;
