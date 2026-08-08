DROP TRIGGER IF EXISTS trg_invoice_status_book ON public.invoices;
CREATE TRIGGER trg_invoice_status_book
  AFTER UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.on_invoice_status_book();

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
  _flag jsonb;
  _admin_email text;
  _tables text[];
  _users_deleted int := 0;
  _skill_count int;
  _settings_count int;
BEGIN
  IF p_confirm IS DISTINCT FROM 'WIPE-SANDBOX' THEN
    RAISE EXCEPTION 'sandbox_reset_wipe requires p_confirm = ''WIPE-SANDBOX''';
  END IF;
  SELECT value INTO _flag FROM public.site_settings WHERE key = 'sandbox_mode';
  IF NOT (_flag = 'true'::jsonb OR (_flag ->> 'enabled') = 'true') THEN
    RAISE EXCEPTION 'sandbox_reset_wipe refused: this instance is not a sandbox (site_settings.sandbox_mode is not true)';
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

CREATE OR REPLACE FUNCTION public.apply_cron_http_timeouts(p_timeout_ms integer DEFAULT 10000)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $fn$
DECLARE
  r          record;
  v_new      text;
  v_updated  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
BEGIN
  IF NOT (auth.role() = 'service_role'
          OR public.has_role(auth.uid(), 'admin')
          OR session_user IN ('postgres', 'supabase_admin')) THEN
    RAISE EXCEPTION 'apply_cron_http_timeouts: admin or service_role required';
  END IF;
  IF p_timeout_ms IS NULL OR p_timeout_ms < 1000 OR p_timeout_ms > 60000 THEN
    RAISE EXCEPTION 'apply_cron_http_timeouts: p_timeout_ms must be 1000..60000 (got %)', p_timeout_ms;
  END IF;
  IF to_regclass('cron.job') IS NULL THEN
    RETURN jsonb_build_object('cron_available', false, 'updated', v_updated, 'skipped', v_skipped);
  END IF;
  FOR r IN
    SELECT jobid, jobname, command
    FROM cron.job
    WHERE command ILIKE '%net.http_post%'
      AND command NOT ILIKE '%timeout_milliseconds%'
  LOOP
    v_new := regexp_replace(
      r.command,
      '\)(\s*(?:AS\s+[a-zA-Z_][a-zA-Z0-9_]*)?\s*;?\s*)$',
      ', timeout_milliseconds := ' || p_timeout_ms || ')\1',
      'i'
    );
    IF v_new IS DISTINCT FROM r.command AND v_new ILIKE '%timeout_milliseconds%' THEN
      PERFORM cron.alter_job(job_id => r.jobid, command => v_new);
      v_updated := v_updated || to_jsonb(r.jobname);
    ELSE
      v_skipped := v_skipped || to_jsonb(r.jobname);
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'cron_available', true,
    'timeout_ms', p_timeout_ms,
    'updated', v_updated,
    'skipped', v_skipped
  );
END
$fn$;

GRANT EXECUTE ON FUNCTION public.apply_cron_http_timeouts(integer) TO authenticated, service_role;

DO $do$
DECLARE
  v_result jsonb;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'apply_cron_http_timeouts: pg_cron not present — sweep skipped.';
    RETURN;
  END IF;
  v_result := public.apply_cron_http_timeouts();
  RAISE NOTICE 'apply_cron_http_timeouts sweep: %', v_result;
END
$do$;

COMMENT ON FUNCTION public.is_staff(uuid) IS
  'True when the user holds at least one non-customer role. Use to gate internal ERP tables so customer-portal accounts cannot write them.';

DO $$
DECLARE
  t text;
  p record;
  targets text[] := ARRAY[
    'vendors','purchase_orders','purchase_order_lines','purchase_order_revisions',
    'rfqs','rfq_bids','rfq_lines','goods_receipts','goods_receipt_lines',
    'vendor_credit_memos','vendor_invoice_disputes',
    'pos_sales','pos_sale_lines','pos_payments','pos_sessions',
    'crm_tasks','deal_history','quote_revisions','quote_attachments',
    'recurring_quote_templates','subscription_plans',
    'project_tasks','ticket_teams','ticket_team_members','ticket_escalation_rules',
    'ticket_time_entries','support_escalations',
    'contract_documents','contract_versions','document_share_links',
    'document_signature_requests','document_versions','content_proposals','wiki_pages'
  ];
BEGIN
  FOREACH t IN ARRAY targets LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      CONTINUE;
    END IF;
    FOR p IN
      SELECT policyname, cmd
        FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = t
         AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
         AND 'authenticated' = ANY(roles)
         AND coalesce(qual, 'true') ~ '^(true)?$'
         AND coalesce(with_check, 'true') ~ '^(true)?$'
    LOOP
      IF p.cmd = 'INSERT' THEN
        EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (public.is_staff(auth.uid()))',
                       p.policyname, t);
      ELSIF p.cmd = 'DELETE' THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (public.is_staff(auth.uid()))',
                       p.policyname, t);
      ELSE
        EXECUTE format('ALTER POLICY %I ON public.%I USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()))',
                       p.policyname, t);
      END IF;
    END LOOP;
  END LOOP;
END $$;