-- Flowtable and River are company-wide; Federation stays admin's.
--
-- The transparency panel made the state visible the moment it shipped
-- (2026-08-13): Flowtable and River granted to no role at all. Both are shared
-- workspaces by design — River is the company stream, Flowtable the data layer
-- any role records into — so they join the shared-surface set from
-- 20260813120000.
--
-- Federation is deliberately NOT granted: peer keys and agent invitations are
-- instance infrastructure, not daily work. Zero matrix rows IS the admin-only
-- state (admin is implicit, never stored), and the panel now says so out loud
-- instead of leaving it to be discovered.
--
-- Same shape as 20260813120000: insert-if-absent into defaults and the live
-- matrix, so an operator's deliberate revocation survives re-runs.

DO $$
DECLARE
  SHARED text[] := ARRAY['flowtable', 'river'];
  m text;
  r record;
BEGIN
  FOREACH m IN ARRAY SHARED LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT DISTINCT d.role, m
      FROM public.role_module_access_defaults d
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = d.role AND x.module_id = m
     );

    INSERT INTO public.role_module_access (role, module_id)
    SELECT DISTINCT a.role, m
      FROM public.role_module_access a
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = a.role AND x.module_id = m
     );
  END LOOP;

  FOR r IN
    SELECT module_id, count(*) AS n FROM public.role_module_access
     WHERE module_id = ANY(SHARED) GROUP BY module_id ORDER BY module_id
  LOOP
    RAISE NOTICE 'company-wide surface % → % role(s)', r.module_id, r.n;
  END LOOP;
END $$;
