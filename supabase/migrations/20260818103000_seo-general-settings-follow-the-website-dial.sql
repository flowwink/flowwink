-- Magnus-beslut 2026-08-18: SEO + general är marknadsfrågor — samma ratt som
-- resten av website-familjen (pages). Mönstret är chat-nyckelns (20260817213000):
-- modulåtkomst = skrivrätt till modulens egna settings-nycklar. Nycklarna som
-- omfattas är sajtens UTÅTRIKTADE identitet (titelmall, OG-bild, hemsideslug);
-- plattformsdriftens nycklar (integrations, modules, email_allowlist …) förblir
-- admin — de är inte website-innehåll.
DROP POLICY IF EXISTS "Website settings editable by pages-module roles" ON public.site_settings;
CREATE POLICY "Website settings editable by pages-module roles" ON public.site_settings
  FOR UPDATE TO authenticated
  USING ((key IN ('seo', 'general', 'cookie_banner')) AND can_access_module(auth.uid(), 'pages'::text))
  WITH CHECK ((key IN ('seo', 'general', 'cookie_banner')) AND can_access_module(auth.uid(), 'pages'::text));

DROP POLICY IF EXISTS "Website settings creatable by pages-module roles" ON public.site_settings;
CREATE POLICY "Website settings creatable by pages-module roles" ON public.site_settings
  FOR INSERT TO authenticated
  WITH CHECK ((key IN ('seo', 'general', 'cookie_banner')) AND can_access_module(auth.uid(), 'pages'::text));
