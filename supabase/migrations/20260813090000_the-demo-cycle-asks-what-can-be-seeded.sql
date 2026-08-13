-- The demo cycle asks what can be seeded instead of carrying a list.
--
-- demo-cycle seeded five modules (crm, quotes, invoices, expenses, ecommerce)
-- from a hardcoded array, while seed_module_demo had grown to THIRTY. On a demo
-- whose whole pitch is "68 modules", twenty-five modules with working seeders
-- sat empty and nobody could tell the difference between "this module has no
-- demo data" and "this module does nothing".
--
-- Same defect class as the template that enabled twelve modules by name
-- (2026-08-12): a snapshot of a growing set, taken once, never revisited. The
-- cure is the same shape — derive it. This function reads the seeder's own CASE
-- branches, so a module added to seed_module_demo is picked up by the nightly
-- cycle with no second edit anywhere. There is exactly one list, and it is the
-- code that does the work.
--
-- Introspection rather than a mirrored array is deliberate: a second copy is a
-- second thing to forget, which is how we got here.

CREATE OR REPLACE FUNCTION public.demo_seedable_modules()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
  SELECT coalesce(array_agg(DISTINCT m[1] ORDER BY m[1]), ARRAY[]::text[])
    FROM pg_proc p
    CROSS JOIN LATERAL regexp_matches(pg_get_functiondef(p.oid), 'WHEN ''([a-z_]+)''', 'g') AS m
   WHERE p.proname = 'seed_module_demo'
     AND p.pronamespace = 'public'::regnamespace;
$$;

COMMENT ON FUNCTION public.demo_seedable_modules() IS
  'Modules seed_module_demo can stage demo data for, read from its own CASE branches. Used by demo-cycle so the nightly run covers every seeder that exists, not a snapshot of the ones that existed when the job was written.';

REVOKE ALL ON FUNCTION public.demo_seedable_modules() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_seedable_modules() TO service_role, authenticated;
