CREATE OR REPLACE FUNCTION public.reset_site_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  KEEP text[] := ARRAY[
    -- identity & access (admin user survives)
    'profiles','user_roles','role_module_access','role_module_access_defaults',
    -- instance config & credentials (Supabase/gateway connections)
    'site_settings','api_keys',
    -- seeded platform layers
    'agent_skills','agent_skill_packs','agent_trust_policies',
    'chart_of_accounts','account_roles','accounting_templates','locale_packs','currencies',
    -- migration bookkeeping
    'schema_migrations','supabase_migrations'
  ];
  _tables text[];
  _skills int;
  _settings int;
  _roles int;
  _profiles int;
BEGIN
  IF p_confirm IS DISTINCT FROM 'RESET-SITE' THEN
    RAISE EXCEPTION 'reset_site_data requires p_confirm = ''RESET-SITE''';
  END IF;

  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role)) THEN
    RAISE EXCEPTION 'Only an admin can reset the site';
  END IF;

  SELECT array_agg(tablename ORDER BY tablename) INTO _tables
    FROM pg_tables
   WHERE schemaname = 'public'
     AND NOT (tablename = ANY(KEEP));

  IF _tables IS NOT NULL AND array_length(_tables, 1) > 0 THEN
    EXECUTE 'TRUNCATE TABLE '
      || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(_tables) AS t)
      || ' RESTART IDENTITY CASCADE';
  END IF;

  SELECT count(*) INTO _skills FROM public.agent_skills;
  SELECT count(*) INTO _settings FROM public.site_settings;
  SELECT count(*) INTO _roles FROM public.user_roles;
  SELECT count(*) INTO _profiles FROM public.profiles;

  IF _skills = 0 OR _settings = 0 OR _roles = 0 OR _profiles = 0 THEN
    RAISE EXCEPTION 'reset_site_data rollback: a keep-table was emptied (skills=%, settings=%, user_roles=%, profiles=%)',
      _skills, _settings, _roles, _profiles;
  END IF;

  RETURN jsonb_build_object(
    'tables_wiped', COALESCE(array_length(_tables, 1), 0),
    'tables_kept', array_length(KEEP, 1),
    'skills_kept', _skills,
    'admins_kept', _roles
  );
END $function$;

REVOKE ALL ON FUNCTION public.reset_site_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_site_data(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_site_data(text) TO service_role;