-- One toggle owns the demo lifecycle.
--
-- Decision (Magnus, 2026-08-12, standing up the new sandbox): "demo toggle
-- finns sedan tidigare — precis av den här anledningen — men allt bör ju hamna
-- under den toggeln." The platform had grown two flags for one idea:
--
--   demo_mode     — the visible System-settings toggle; scheduled demo-cycle,
--                   which only re-staged module scenario data
--   sandbox_mode  — set by hand on exactly one instance; gated the FULL
--                   nightly destroy-and-rebuild (this wipe + template reinstall)
--
-- Two flags for "this instance is disposable" is the two-generations trap:
-- the toggle a user can see did the shallow thing, and the deep thing hid
-- behind a setting no UI writes. From here the ONE toggle carries the whole
-- contract: demo mode ON means the instance is rebuilt to its template nightly
-- — content, users, everything. The DemoModeCard states that blast radius out
-- loud; the toggle being explicit about consequences is what makes a single
-- toggle safe.
--
-- The wipe therefore gates on demo_mode. sandbox_mode is still honored so the
-- old sandbox instance keeps working until it is retired; new instances never
-- set it. Everything else — confirm token, role gate, keep-list, atomic
-- rollback invariants — is unchanged from 20260722200000.
--
-- The toggle's value also grows a template_id: {"enabled": true, "template_id":
-- "demo-company"} — which template the nightly rebuild restores. A bare `true`
-- keeps working (older card versions wrote that).

CREATE OR REPLACE FUNCTION public.sandbox_reset_wipe(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  -- Survives every reset: seeded layers (skills, automations, chart, roles,
  -- accounting templates, locale packs), instance config, identity, gateway
  -- credentials, and the demo-cycle registry definitions live in cron/config.
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

  -- One TRUNCATE over the whole wipe set. CASCADE only ever reaches tables
  -- OUTSIDE the set — and if that turns out to be a keep-table, the invariant
  -- check below rolls the whole transaction back.
  SELECT array_agg(tablename ORDER BY tablename) INTO _tables
    FROM pg_tables
   WHERE schemaname = 'public'
     AND NOT (tablename = ANY(KEEP));

  IF _tables IS NOT NULL AND array_length(_tables, 1) > 0 THEN
    EXECUTE 'TRUNCATE TABLE '
      || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(_tables) AS t)
      || ' RESTART IDENTITY CASCADE';
  END IF;

  -- Auth normalize: every account except the shared sandbox admin goes; the
  -- admin's password resets to the published demo credential. A tester who
  -- changed the password or invited themselves as a second admin is undone
  -- here — nightly, automatically.
  DELETE FROM auth.users WHERE lower(email) IS DISTINCT FROM lower(_admin_email);
  GET DIAGNOSTICS _users_deleted = ROW_COUNT;
  UPDATE auth.users
     SET encrypted_password = extensions.crypt('demo1234', extensions.gen_salt('bf')),
         email_confirmed_at = COALESCE(email_confirmed_at, now())
   WHERE lower(email) = lower(_admin_email);

  -- Invariants: the seeded layers and config must have survived. If a foreign
  -- key quietly cascaded into them, refuse the whole wipe.
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

-- Deliberately NOT granted to authenticated: the skill rail (service_role via
-- agent-execute) and admins-through-the-rail are the only callers.
REVOKE ALL ON FUNCTION public.sandbox_reset_wipe(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sandbox_reset_wipe(text) TO service_role;
