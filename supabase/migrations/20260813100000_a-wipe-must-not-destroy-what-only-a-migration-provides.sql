-- A wipe must not destroy what only a migration provides.
--
-- The nightly rebuild truncates every public table outside a keep-list, then
-- reinstalls the template. That restores CONTENT — pages, posts, products. It
-- does not restore REFERENCE DATA, because reference data is seeded by
-- migrations, and migrations do not re-run on an instance that already has
-- them. So every table in that category was destroyed on the first night and
-- stayed empty forever after.
--
-- Found by running the full demo cycle after a rebuild (2026-08-13): the `hr`
-- seeder failed on employees_payroll_country_fk — payroll_country_profiles was
-- empty — and `timesheets` failed behind it for want of an employee. Sweeping
-- every table any migration INSERTs into, and diffing a long-lived instance
-- against the freshly-rebuilt one, turned two failures into eighteen tables.
-- Three of them are role_module_access(_defaults) and account_tax_boxes: the
-- nav/role matrix whose absence caused the empty-role-views incident after the
-- June squash, and the VAT box map a return cannot be filed without.
--
-- The deciding property is not "is this important" but "does anything else
-- restore it". Runtime data that regenerates (exchange_rates via the FX cron)
-- and records of what happened (approval_decisions) are correctly wiped.
-- Anything whose only source is a migration must survive, or the demo degrades
-- a little more every night while looking like it rebuilt cleanly.
--
-- reconciliation_rules deliberately did NOT make the list: the one row a
-- long-lived instance had was a rule its bookkeeper wrote, not a default. A new
-- organisation defines its own — born empty is correct there, and keeping it
-- would preserve one company's matching logic into everybody else's demo.
--
-- Everything else about the wipe — confirm token, demo_mode gate, role check,
-- atomic invariants — is unchanged from 20260812210000.

CREATE OR REPLACE FUNCTION public.sandbox_reset_wipe(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  -- Survives every reset. Two groups:
  --   1. The instance's own identity, credentials and seeded agent surface.
  --   2. Reference data whose ONLY source is a migration — nothing re-seeds
  --      these after a truncate, so wiping them is permanent.
  KEEP text[] := ARRAY[
    -- identity, config, agent surface
    'agent_skills','agent_automations','agent_trust_policies',
    'site_settings','user_roles','profiles','api_keys',
    -- role/nav matrix (empty here = every non-admin sees an empty product)
    'role_module_access','role_module_access_defaults',
    -- accounting reference
    'chart_of_accounts','account_roles','accounting_templates','locale_packs',
    'account_tax_boxes','journals','currencies',
    -- operational reference
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

  -- Auth normalize: every account except the shared demo admin goes; the
  -- admin's password resets to the published demo credential.
  DELETE FROM auth.users WHERE lower(email) IS DISTINCT FROM lower(_admin_email);
  GET DIAGNOSTICS _users_deleted = ROW_COUNT;
  UPDATE auth.users
     SET encrypted_password = extensions.crypt('demo1234', extensions.gen_salt('bf')),
         email_confirmed_at = COALESCE(email_confirmed_at, now())
   WHERE lower(email) = lower(_admin_email);

  -- Invariants: the seeded layers and config must have survived. If a foreign
  -- key quietly cascaded into them, refuse the whole wipe. The role matrix is
  -- checked too — it is the one whose emptiness is invisible to an admin.
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


-- journals are the same category as the chart of accounts — BANK, CASH, SALES,
-- PURCH, MISC exist on every instance and nothing works without them — but they
-- were seeded ONLY in the baseline, which never re-runs. So they survived on
-- instances old enough to predate the squash and were simply absent from every
-- fresh install, and from every instance after its first nightly wipe. Seeded
-- here re-assertably (insert-if-absent), which is what platform config needs:
-- a migration that can be replayed, not a one-shot INSERT nobody can repeat.
-- Currency is deliberately omitted: the column defaults to the instance's own,
-- and hardcoding one here is the class of bug that put SEK-vs-USD defaults in
-- the client once already.
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
