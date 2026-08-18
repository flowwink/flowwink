-- ui_text är besökartext (kakbanner, chattens småtexter, sökets tomlägen) —
-- samma familj som seo/general/cookie_banner (20260818103000). Nyckeln läggs
-- till i website-dialens policy så Lead capture-kortet i AI Chat-inställningarna
-- kan spara för pages-beviljade roller.
DROP POLICY IF EXISTS "Website settings editable by pages-module roles" ON public.site_settings;
CREATE POLICY "Website settings editable by pages-module roles" ON public.site_settings
  FOR UPDATE TO authenticated
  USING ((key IN ('seo', 'general', 'cookie_banner', 'ui_text')) AND can_access_module(auth.uid(), 'pages'::text))
  WITH CHECK ((key IN ('seo', 'general', 'cookie_banner', 'ui_text')) AND can_access_module(auth.uid(), 'pages'::text));

DROP POLICY IF EXISTS "Website settings creatable by pages-module roles" ON public.site_settings;
CREATE POLICY "Website settings creatable by pages-module roles" ON public.site_settings
  FOR INSERT TO authenticated
  WITH CHECK ((key IN ('seo', 'general', 'cookie_banner', 'ui_text')) AND can_access_module(auth.uid(), 'pages'::text));
