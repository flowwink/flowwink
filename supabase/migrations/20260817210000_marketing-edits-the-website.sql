-- Marketing edits the website (Svante-fyndet 2026-08-17): the role had blog,
-- newsletter, KB and wiki — every surface that writes ABOUT the site — but not
-- pages or mediaLibrary, the two modules that edit the site itself. Marketing
-- owning the website is the common case, so it becomes the DEFAULT; an
-- operator who disagrees unticks it in Role Permissions (the matrix stays the
-- only dial). Insert-if-absent everywhere: operator customisations survive.
INSERT INTO public.role_module_access_defaults (role, module_id)
SELECT v.role::app_role, v.module_id FROM (VALUES
  ('marketing','pages'), ('marketing','mediaLibrary')
) AS v(role, module_id)
WHERE NOT EXISTS (SELECT 1 FROM public.role_module_access_defaults d
                  WHERE d.role = v.role::app_role AND d.module_id = v.module_id);

INSERT INTO public.role_module_access (role, module_id)
SELECT v.role::app_role, v.module_id FROM (VALUES
  ('marketing','pages'), ('marketing','mediaLibrary')
) AS v(role, module_id)
WHERE NOT EXISTS (SELECT 1 FROM public.role_module_access a
                  WHERE a.role = v.role::app_role AND a.module_id = v.module_id);
