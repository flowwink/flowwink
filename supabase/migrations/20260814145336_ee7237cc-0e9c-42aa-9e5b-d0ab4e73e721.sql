-- === 20260812190000_outbound-cron-follows-the-instance.sql ===
CREATE OR REPLACE FUNCTION public.register_knowledge_indexer_cron(p_supabase_url text, p_anon_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
DECLARE
  v_own_host   text;
  v_headers    text;
  v_result     jsonb := '{}'::jsonb;
  v_command    text;
  r            record;
BEGIN
  IF NOT (auth.role() = 'service_role' OR public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Only admins can register cron jobs';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN jsonb_build_object('status', 'pg_cron_missing');
  END IF;

  v_own_host := substring(p_supabase_url from '^https?://[^/]+');
  IF v_own_host IS NULL THEN
    RAISE EXCEPTION 'p_supabase_url does not look like a URL: %', p_supabase_url;
  END IF;

  v_headers := json_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || p_anon_key
  )::text;

  FOR r IN SELECT * FROM (VALUES
    ('knowledge-indexer',             '*/5 * * * *', 'knowledge-indexer'),
    ('newsletter-dispatch-scheduled', '*/5 * * * *', 'newsletter/dispatch-scheduled')
  ) AS t(jobname, schedule, fn_path)
  LOOP
    v_command := format(
      'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source":"cron"}''::jsonb) AS request_id;',
      p_supabase_url || '/functions/v1/' || r.fn_path,
      v_headers
    );

    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = r.jobname) THEN
      PERFORM cron.schedule(r.jobname, r.schedule, v_command);
      v_result := v_result || jsonb_build_object(r.jobname, 'registered');
    ELSIF EXISTS (
      SELECT 1 FROM cron.job
      WHERE jobname = r.jobname
        AND substring(command from 'https?://[^/'']+') IS DISTINCT FROM v_own_host
    ) THEN
      PERFORM cron.alter_job(
        (SELECT jobid FROM cron.job WHERE jobname = r.jobname),
        command := v_command,
        active  := true
      );
      v_result := v_result || jsonb_build_object(r.jobname, 're-anchored');
    ELSE
      v_result := v_result || jsonb_build_object(r.jobname, 'ok');
    END IF;
  END LOOP;

  FOR r IN
    SELECT jobid, jobname
      FROM cron.job
     WHERE command LIKE '%/functions/v1/%'
       AND active
       AND jobname NOT IN ('knowledge-indexer', 'newsletter-dispatch-scheduled')
       AND substring(command from 'https?://[^/'']+') IS DISTINCT FROM v_own_host
  LOOP
    PERFORM cron.alter_job(r.jobid, active := false);
    RAISE NOTICE 'cron job % pointed at a foreign instance — deactivated (re-register it with this instance''s identity)', r.jobname;
    v_result := v_result || jsonb_build_object(r.jobname, 'deactivated_foreign_host');
  END LOOP;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_retrieval_cron(p_supabase_url text, p_anon_key text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.register_knowledge_indexer_cron(p_supabase_url, p_anon_key);
$$;

GRANT EXECUTE ON FUNCTION public.register_retrieval_cron(text, text) TO authenticated, service_role;

-- === 20260812200000_migration-seeded-skills-follow-the-edge-surface.sql ===
UPDATE public.agent_skills
   SET handler = 'edge:comms-send'
 WHERE name = 'send_webinar_reminders'
   AND handler = 'edge:send-webinar-reminders';

-- === 20260813120000_shared-surfaces-belong-to-every-role.sql ===
DO $$
DECLARE
  SHARED text[] := ARRAY['wiki', 'knowledgeBase', 'docs', 'documents', 'workspaceChat', 'handbook'];
  r record;
  m text;
BEGIN
  FOREACH m IN ARRAY SHARED LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT DISTINCT d.role, m
      FROM public.role_module_access_defaults d
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = d.role AND x.module_id = m
     );
  END LOOP;

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