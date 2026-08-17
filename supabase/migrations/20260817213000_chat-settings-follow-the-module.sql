-- Chat settings editable by chat-module holders (Svante-fyndet #2, 2026-08-17):
-- Svante (sales+marketing, chat module granted) edited the system prompt and
-- the save silently did nothing — site_settings UPDATE was admin-only, and a
-- 0-row update returns no error. The chat is outward communication, owned in
-- practice by marketing; company_profile already follows this exact pattern
-- (module access = write access to the module's own settings row). Same dial,
-- same rule: the matrix decides.
DROP POLICY IF EXISTS "Chat settings editable by its module roles" ON public.site_settings;
CREATE POLICY "Chat settings editable by its module roles" ON public.site_settings
  FOR UPDATE TO authenticated
  USING ((key = 'chat'::text) AND can_access_module(auth.uid(), 'chat'::text))
  WITH CHECK ((key = 'chat'::text) AND can_access_module(auth.uid(), 'chat'::text));

DROP POLICY IF EXISTS "Chat settings creatable by its module roles" ON public.site_settings;
CREATE POLICY "Chat settings creatable by its module roles" ON public.site_settings
  FOR INSERT TO authenticated
  WITH CHECK ((key = 'chat'::text) AND can_access_module(auth.uid(), 'chat'::text));
