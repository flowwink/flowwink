-- Pipeline stages are PLATFORM CONFIG, and must exist on every instance.
--
-- Found by a fleet sweep 2026-08-08: dev and the sandbox had pipeline_stages
-- COMPLETELY EMPTY — all three entity types, zero rows — while optic/liteit/www
-- carried the full 17. Both had the original seeding migration in their ledger,
-- so the rows were created and later lost (a reset/rebuild that truncated
-- platform config along with business data). The consequence is not subtle: the
-- deal, lead and ticket kanbans render NO columns, and since today's "one truth"
-- change the stage dropdowns and pipeline stats fall back to hardcoded lists —
-- the whole point of configurable stages disappears.
--
-- This is the same class as the role_module_access_defaults incident: platform
-- config (nav/pipeline/role behaviour) MUST be seeded and MUST be re-assertable,
-- unlike business config (carriers, approval rules) where born-empty is correct.
--
-- Idempotent and non-destructive by construction:
--   * a stage that already exists is left ALONE — an operator who renamed
--     "Prospecting" to "Discovery", changed a probability, or deactivated a
--     stage keeps their customisation
--   * only genuinely missing (entity_type, key) pairs are inserted
--   * forward-dated so managed runners (Lovable) apply it above their ledger head
CREATE OR REPLACE FUNCTION public.seed_default_pipeline_stages()
RETURNS TABLE(inserted integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_count integer;
BEGIN
  WITH defaults(entity_type, key, name, sort_order, probability, is_won, is_lost, fold) AS (
    VALUES
      ('deal','lead','Lead',10,10::numeric,false,false,false),
      ('deal','prospecting','Prospecting',20,20::numeric,false,false,false),
      ('deal','qualified','Qualified',30,40::numeric,false,false,false),
      ('deal','proposal','Proposal',40,60::numeric,false,false,false),
      ('deal','negotiation','Negotiation',50,80::numeric,false,false,false),
      ('deal','closed_won','Closed Won',60,100::numeric,true,false,false),
      ('deal','closed_lost','Closed Lost',70,0::numeric,false,true,true),
      ('lead','lead','Lead',10,10::numeric,false,false,false),
      ('lead','opportunity','Opportunity',20,40::numeric,false,false,false),
      ('lead','customer','Customer',30,100::numeric,true,false,false),
      ('lead','lost','Lost',40,0::numeric,false,true,true),
      ('ticket','new','New',10,NULL::numeric,false,false,false),
      ('ticket','open','Open',20,NULL::numeric,false,false,false),
      ('ticket','in_progress','In Progress',30,NULL::numeric,false,false,false),
      ('ticket','waiting','Waiting',40,NULL::numeric,false,false,false),
      ('ticket','resolved','Resolved',50,NULL::numeric,true,false,true),
      ('ticket','closed','Closed',60,NULL::numeric,true,false,true)
  )
  INSERT INTO public.pipeline_stages (entity_type, key, name, sort_order, probability, is_won, is_lost, fold)
  SELECT d.entity_type, d.key, d.name, d.sort_order, d.probability, d.is_won, d.is_lost, d.fold
  FROM defaults d
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pipeline_stages p
     WHERE p.entity_type = d.entity_type AND p.key = d.key
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN QUERY SELECT v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_default_pipeline_stages() TO service_role;

-- Run it now, and leave the function behind so a rebuild/reset can re-assert
-- the platform's own configuration without a migration replay.
SELECT public.seed_default_pipeline_stages();
