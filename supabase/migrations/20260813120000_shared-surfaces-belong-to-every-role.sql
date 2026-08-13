-- Shared surfaces belong to every role.
--
-- Found by opening the product as a salesperson (Magnus, 2026-08-13): no
-- FlowWork, no wiki, no knowledge base, no docs, no documents — and no access
-- to their own profile page. Two independent gates were denying, and only one
-- of them was data:
--
--   • the nav's hardcoded group roles (fixed in adminNavigation.ts: FlowWork
--     sat in the support-only group, Profile in the adminOnly group)
--   • this matrix, where the shared surfaces were granted to almost nobody
--
-- The defaults said: documents → accounting/hr/projects, handbook → hr,
-- workspaceChat → support, and wiki / knowledgeBase / docs → NO ROLE AT ALL.
-- Those three were reachable by admins only, on every instance, which is not a
-- stale-data problem — it was our own seeded intent.
--
-- Knowledge and the shared workroom are not departmental property. A
-- salesperson who cannot read the handbook or search the knowledge base is
-- worse at their job, and the organisation gets a second copy of that content
-- somewhere the platform cannot see. Handbook joins them: like docs, its
-- content originates in a repository and is published INTO the instance —
-- read-many by nature.
--
-- Module toggles still apply: these grants say "this role may use the module IF
-- the instance has it enabled". A site without a wiki still shows no wiki.
--
-- Idempotent and re-assertable: inserts only what is missing, so an operator
-- who deliberately revoked a grant keeps their decision on the live table while
-- the defaults stay complete.

DO $$
DECLARE
  SHARED text[] := ARRAY['wiki', 'knowledgeBase', 'docs', 'documents', 'workspaceChat', 'handbook'];
  r record;
  m text;
BEGIN
  -- 1. Defaults: every role that exists in the defaults table gets all six.
  FOREACH m IN ARRAY SHARED LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT DISTINCT d.role, m
      FROM public.role_module_access_defaults d
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = d.role AND x.module_id = m
     );
  END LOOP;

  -- 2. The live matrix: same grants, for the roles this instance actually uses.
  -- Instances provisioned before a module existed never received it — autoversio's
  -- rows were written in May and had never seen a module shipped since.
  FOREACH m IN ARRAY SHARED LOOP
    INSERT INTO public.role_module_access (role, module_id)
    SELECT DISTINCT a.role, m
      FROM public.role_module_access a
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = a.role AND x.module_id = m
     );
  END LOOP;

  FOR r IN
    SELECT module_id, count(*) AS n
      FROM public.role_module_access
     WHERE module_id = ANY(SHARED)
     GROUP BY module_id ORDER BY module_id
  LOOP
    RAISE NOTICE 'shared surface % → % role(s)', r.module_id, r.n;
  END LOOP;
END $$;
