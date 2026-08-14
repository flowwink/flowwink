-- === 20260812210000_one-toggle-owns-the-demo-lifecycle.sql ===
CREATE OR REPLACE FUNCTION public.sandbox_reset_wipe(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  KEEP text[] := ARRAY[
    'agent_skills','agent_automations',
    'chart_of_accounts','account_roles','accounting_templates','locale_packs',
    'site_settings','user_roles','profiles','api_keys'
  ];
  _demo jsonb;
  _legacy jsonb;
  _admin_email text;
  _tables text[];
  _users_deleted int := 0;
  _skill_count int;
  _settings_count int;
BEGIN
  IF p_confirm IS DISTINCT FROM 'WIPE-SANDBOX' THEN
    RAISE EXCEPTION 'sandbox_reset_wipe requires p_confirm = ''WIPE-SANDBOX''';
  END IF;

  SELECT value INTO _demo   FROM public.site_settings WHERE key = 'demo_mode';
  SELECT value INTO _legacy FROM public.site_settings WHERE key = 'sandbox_mode';
  IF NOT (
       _demo = 'true'::jsonb OR (_demo ->> 'enabled') = 'true'
    OR _legacy = 'true'::jsonb OR (_legacy ->> 'enabled') = 'true'
  ) THEN
    RAISE EXCEPTION 'sandbox_reset_wipe refused: this instance is not a demo (site_settings.demo_mode is not enabled)';
  END IF;

  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role)) THEN
    RAISE EXCEPTION 'Only service_role or an admin can reset the sandbox';
  END IF;

  SELECT COALESCE(
    NULLIF((SELECT value #>> '{}' FROM public.site_settings WHERE key = 'sandbox_admin_email'), ''),
    'demo@flowwink.com'
  ) INTO _admin_email;

  SELECT array_agg(tablename ORDER BY tablename) INTO _tables
    FROM pg_tables
   WHERE schemaname = 'public'
     AND NOT (tablename = ANY(KEEP));

  IF _tables IS NOT NULL AND array_length(_tables, 1) > 0 THEN
    EXECUTE 'TRUNCATE TABLE '
      || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(_tables) AS t)
      || ' RESTART IDENTITY CASCADE';
  END IF;

  DELETE FROM auth.users WHERE lower(email) IS DISTINCT FROM lower(_admin_email);
  GET DIAGNOSTICS _users_deleted = ROW_COUNT;
  UPDATE auth.users
     SET encrypted_password = extensions.crypt('demo1234', extensions.gen_salt('bf')),
         email_confirmed_at = COALESCE(email_confirmed_at, now())
   WHERE lower(email) = lower(_admin_email);

  SELECT count(*) INTO _skill_count FROM public.agent_skills;
  SELECT count(*) INTO _settings_count FROM public.site_settings;
  IF _skill_count = 0 OR _settings_count = 0 THEN
    RAISE EXCEPTION 'sandbox_reset_wipe rollback: a keep-table was emptied (agent_skills=%, site_settings=%)',
      _skill_count, _settings_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(_admin_email)) THEN
    RAISE EXCEPTION 'sandbox_reset_wipe rollback: sandbox admin % missing after auth normalize', _admin_email;
  END IF;

  RETURN jsonb_build_object(
    'tables_wiped', COALESCE(array_length(_tables, 1), 0),
    'users_deleted', _users_deleted,
    'admin_email', _admin_email,
    'skills_kept', _skill_count
  );
END $function$;

REVOKE ALL ON FUNCTION public.sandbox_reset_wipe(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sandbox_reset_wipe(text) TO service_role;

-- === 20260813070000_the-fourth-layer-can-bootstrap-itself.sql ===
INSERT INTO public.agent_skills
  (name, description, category, handler, scope, tool_definition, enabled, mcp_exposed, origin, trust_level, requires_staging)
SELECT
  'sync_skills_from_code',
  'Reconcile this instance''s skill registry against the deployed code''s bundled seed artifact. Inserts missing skills, refreshes drifted definition fields, never touches trust_level. Use when: skills look stale or missing after a deploy.',
  'system',
  'internal:sync_skills_from_code',
  'internal',
  '{"type":"function","function":{"name":"sync_skills_from_code","description":"Reconcile agent_skills against the deploy''s bundled seed artifact — insert missing, refresh drifted, never touch trust_level. Idempotent; hash-gated.","parameters":{"type":"object","properties":{"force":{"type":"boolean","description":"Re-apply even when the artifact hash matches."}}}}}'::jsonb,
  true, true, 'bundled', 'auto', false
WHERE NOT EXISTS (
  SELECT 1 FROM public.agent_skills WHERE name = 'sync_skills_from_code'
);

-- === 20260813100000_a-wipe-must-not-destroy-what-only-a-migration-provides.sql ===
CREATE OR REPLACE FUNCTION public.sandbox_reset_wipe(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  KEEP text[] := ARRAY[
    'agent_skills','agent_automations','agent_trust_policies',
    'site_settings','user_roles','profiles','api_keys',
    'role_module_access','role_module_access_defaults',
    'chart_of_accounts','account_roles','accounting_templates','locale_packs',
    'account_tax_boxes','journals','currencies',
    'payroll_country_profiles','expense_rate_tables','postal_code_rules',
    'pipeline_stages','business_hours',
    'uoms','uom_categories'
  ];
  _demo jsonb;
  _legacy jsonb;
  _admin_email text;
  _tables text[];
  _users_deleted int := 0;
  _skill_count int;
  _settings_count int;
  _roles_count int;
BEGIN
  IF p_confirm IS DISTINCT FROM 'WIPE-SANDBOX' THEN
    RAISE EXCEPTION 'sandbox_reset_wipe requires p_confirm = ''WIPE-SANDBOX''';
  END IF;

  SELECT value INTO _demo   FROM public.site_settings WHERE key = 'demo_mode';
  SELECT value INTO _legacy FROM public.site_settings WHERE key = 'sandbox_mode';
  IF NOT (
       _demo = 'true'::jsonb OR (_demo ->> 'enabled') = 'true'
    OR _legacy = 'true'::jsonb OR (_legacy ->> 'enabled') = 'true'
  ) THEN
    RAISE EXCEPTION 'sandbox_reset_wipe refused: this instance is not a demo (site_settings.demo_mode is not enabled)';
  END IF;

  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role)) THEN
    RAISE EXCEPTION 'Only service_role or an admin can reset the sandbox';
  END IF;

  SELECT COALESCE(
    NULLIF((SELECT value #>> '{}' FROM public.site_settings WHERE key = 'sandbox_admin_email'), ''),
    'demo@flowwink.com'
  ) INTO _admin_email;

  SELECT array_agg(tablename ORDER BY tablename) INTO _tables
    FROM pg_tables
   WHERE schemaname = 'public'
     AND NOT (tablename = ANY(KEEP));

  IF _tables IS NOT NULL AND array_length(_tables, 1) > 0 THEN
    EXECUTE 'TRUNCATE TABLE '
      || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(_tables) AS t)
      || ' RESTART IDENTITY CASCADE';
  END IF;

  DELETE FROM auth.users WHERE lower(email) IS DISTINCT FROM lower(_admin_email);
  GET DIAGNOSTICS _users_deleted = ROW_COUNT;
  UPDATE auth.users
     SET encrypted_password = extensions.crypt('demo1234', extensions.gen_salt('bf')),
         email_confirmed_at = COALESCE(email_confirmed_at, now())
   WHERE lower(email) = lower(_admin_email);

  SELECT count(*) INTO _skill_count FROM public.agent_skills;
  SELECT count(*) INTO _settings_count FROM public.site_settings;
  SELECT count(*) INTO _roles_count FROM public.role_module_access_defaults;
  IF _skill_count = 0 OR _settings_count = 0 THEN
    RAISE EXCEPTION 'sandbox_reset_wipe rollback: a keep-table was emptied (agent_skills=%, site_settings=%)',
      _skill_count, _settings_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(_admin_email)) THEN
    RAISE EXCEPTION 'sandbox_reset_wipe rollback: sandbox admin % missing after auth normalize', _admin_email;
  END IF;

  RETURN jsonb_build_object(
    'tables_wiped', COALESCE(array_length(_tables, 1), 0),
    'users_deleted', _users_deleted,
    'admin_email', _admin_email,
    'skills_kept', _skill_count,
    'role_defaults_kept', _roles_count
  );
END $function$;

REVOKE ALL ON FUNCTION public.sandbox_reset_wipe(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sandbox_reset_wipe(text) TO service_role;

INSERT INTO public.journals (code, name, journal_type)
SELECT v.code, v.name, v.journal_type
FROM (VALUES
  ('BANK',  'Bank',             'bank'),
  ('CASH',  'Cash',             'cash'),
  ('MISC',  'Miscellaneous',    'misc'),
  ('PURCH', 'Purchase Journal', 'purchase'),
  ('SALES', 'Sales Journal',    'sales')
) AS v(code, name, journal_type)
WHERE NOT EXISTS (SELECT 1 FROM public.journals j WHERE j.code = v.code);