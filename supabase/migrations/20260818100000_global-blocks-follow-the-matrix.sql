-- Svante-fynd 2026-08-18: marketing (pages+mediaLibrary beviljade) kunde inte
-- spara footern — global_blocks skrivpolicies var admin-literaler (#102-
-- klassen; tabellen missades i både 220000 och 235000). Header/footer
-- redigeras under Pages-ytan men ägs av globalElements-modulen (skill-vägen
-- grindar redan på den), så policyn tar båda benen och marketing seedas med
-- globalElements — EN sanning oavsett kodväg (POS Audit-lärdomen).

DO $$
BEGIN
  IF to_regclass('public.global_blocks') IS NOT NULL THEN
    DROP POLICY IF EXISTS "website modules update global_blocks" ON public.global_blocks;
    CREATE POLICY "website modules update global_blocks" ON public.global_blocks
      FOR UPDATE USING (public.can_access_module(auth.uid(), 'pages')
                        OR public.can_access_module(auth.uid(), 'globalElements'))
      WITH CHECK (public.can_access_module(auth.uid(), 'pages')
                  OR public.can_access_module(auth.uid(), 'globalElements'));

    DROP POLICY IF EXISTS "website modules insert global_blocks" ON public.global_blocks;
    CREATE POLICY "website modules insert global_blocks" ON public.global_blocks
      FOR INSERT WITH CHECK (public.can_access_module(auth.uid(), 'pages')
                             OR public.can_access_module(auth.uid(), 'globalElements'));
  END IF;

  INSERT INTO public.role_module_access_defaults (role, module_id)
  VALUES ('marketing'::public.app_role, 'globalElements') ON CONFLICT DO NOTHING;
  INSERT INTO public.role_module_access (role, module_id)
  VALUES ('marketing'::public.app_role, 'globalElements') ON CONFLICT DO NOTHING;
END $$;
