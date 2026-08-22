-- event-dispatcher joins the runtime registrar.
--
-- THE DEADLOCK
-- ------------
-- The only thing in the repository that has ever scheduled
-- `event-dispatcher-every-minute` is migration 20260808130000. It reads
-- SUPABASE_URL out of the vault and bails when the vault is empty:
--
--     IF _url IS NULL OR length(_url) = 0 THEN
--       RAISE NOTICE 'vault has no SUPABASE_URL yet — event-dispatcher not scheduled.'
--       RETURN;
--
-- A fresh vault has zero secrets. The vault is filled by automation-dispatcher
-- (ensure_platform_secret, every tick) — which needs ITS cron job — which is
-- registered by register_flowpilot_cron — which an admin triggers by toggling a
-- module. And the migration never runs a second time, because the ledger has
-- already recorded it. So on every instance born after 2026-08-08 the whole
-- event-driven lane is dead from birth: agent_events accumulates forever,
-- nothing drains it, and the seeded "Notify approvers in cowork chat"
-- automation never fires. The comment in that file even says "the next run of
-- this migration will pick it up" — there is no next run.
--
-- Verified before writing this: 'event-dispatcher-every-minute' appears in
-- neither register_flowpilot_cron (6 jobs: heartbeat, automation-dispatcher,
-- publish-scheduled-pages, flowpilot-learn, daily-briefing, instance-health)
-- nor register_knowledge_indexer_cron (knowledge-indexer,
-- newsletter-dispatch-scheduled).
--
-- THE FIX
-- -------
-- Put it where the other per-minute tick already lives. The registrar is a
-- RUNTIME function: the browser knows the instance's own URL and anon key,
-- which Postgres cannot derive, and module-bootstrap calls it on every
-- bootstrap (ensurePlatformCron). "IF NOT EXISTS against cron.job" makes
-- re-registration free, which is exactly why adding a 7th job here reaches
-- existing instances too — the next bootstrap picks it up — while a migration
-- reaches nobody who is already past it.
--
-- The general rule this instance belongs to is now a guardrail:
-- cron-jobs-have-a-runtime-registrar.guardrails.test.ts. A cron job that only
-- a migration can schedule is unrecoverable the moment that migration is
-- skipped, backdated below a ledger head, or bails on a precondition.
--
-- event-dispatcher runs with verify_jwt = false (supabase/config.toml), so the
-- anon key the registrar already carries is the right credential — no vault
-- read, no service-role key baked into a cron command. timeout_milliseconds
-- matches the per-minute dispatcher convention so a hung invocation cannot
-- stack up minute over minute.
--
-- The body below is the 2026-08-22 definition (20260822040000, anon guards)
-- reproduced verbatim, plus block 7. Idempotent: CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.register_flowpilot_cron(p_supabase_url text, p_anon_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
DECLARE
  result jsonb := '{}'::jsonb;
  job_exists boolean;
  auth_header text;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role)) THEN
    RAISE EXCEPTION 'unauthorized: cron scheduling requires admin or service role';
  END IF;

  auth_header := json_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || p_anon_key
  )::text;

  -- 1. Heartbeat (every 12h)
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'flowpilot-heartbeat') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'flowpilot-heartbeat',
      '0 0,12 * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := concat(''{"time":"'', now(), ''"}'')::jsonb) AS request_id;',
        p_supabase_url || '/functions/v1/flowpilot-heartbeat',
        auth_header
      )
    );
    result := result || '{"heartbeat": "registered"}'::jsonb;
  ELSE
    result := result || '{"heartbeat": "already_exists"}'::jsonb;
  END IF;

  -- 2. Automation dispatcher (every minute)
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'automation-dispatcher-every-minute') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'automation-dispatcher-every-minute',
      '* * * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source": "pg_cron"}''::jsonb) AS request_id;',
        p_supabase_url || '/functions/v1/automation-dispatcher',
        auth_header
      )
    );
    result := result || '{"automation_dispatcher": "registered"}'::jsonb;
  ELSE
    result := result || '{"automation_dispatcher": "already_exists"}'::jsonb;
  END IF;

  -- 3. Publish scheduled pages (every 5 minutes). The logic is the DB function
  --    public.publish_scheduled_pages() — call it directly. There is NO edge
  --    function by this name; the old HTTP wiring 404ed every 5 minutes.
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'publish-scheduled-pages') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'publish-scheduled-pages',
      '*/5 * * * *',
      'SELECT public.publish_scheduled_pages();'
    );
    result := result || '{"publish_scheduled_pages": "registered"}'::jsonb;
  ELSE
    result := result || '{"publish_scheduled_pages": "already_exists"}'::jsonb;
  END IF;

  -- 4. FlowPilot learn (daily at 03:00)
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'flowpilot-learn') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'flowpilot-learn',
      '0 3 * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := concat(''{"time":"'', now(), ''"}'')::jsonb) AS request_id;',
        p_supabase_url || '/functions/v1/flowpilot-learn',
        auth_header
      )
    );
    result := result || '{"flowpilot_learn": "registered"}'::jsonb;
  ELSE
    result := result || '{"flowpilot_learn": "already_exists"}'::jsonb;
  END IF;

  -- 5. Daily briefing (daily at 07:00)
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'flowpilot-daily-briefing') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'flowpilot-daily-briefing',
      '0 7 * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source": "cron"}''::jsonb) AS request_id;',
        p_supabase_url || '/functions/v1/flowpilot-briefing',
        auth_header
      )
    );
    result := result || '{"daily_briefing": "registered"}'::jsonb;
  ELSE
    result := result || '{"daily_briefing": "already_exists"}'::jsonb;
  END IF;

  -- 6. Instance health check (every 6 hours)
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'instance-health-check') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'instance-health-check',
      '0 */6 * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source": "cron"}''::jsonb) AS request_id;',
        p_supabase_url || '/functions/v1/instance-health',
        auth_header
      )
    );
    result := result || '{"instance_health_check": "registered"}'::jsonb;
  ELSE
    result := result || '{"instance_health_check": "already_exists"}'::jsonb;
  END IF;

  -- 7. Event dispatcher (every minute). Drains agent_events — the second half
  --    of the automation lane; without it DB-born events are recorded and
  --    never delivered. Migration 20260808130000 was the only scheduler and it
  --    bails on an empty vault, which is the state of every fresh install.
  SELECT EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'event-dispatcher-every-minute') INTO job_exists;
  IF NOT job_exists THEN
    PERFORM cron.schedule(
      'event-dispatcher-every-minute',
      '* * * * *',
      format(
        'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source": "pg_cron"}''::jsonb, timeout_milliseconds := 10000) AS request_id;',
        p_supabase_url || '/functions/v1/event-dispatcher',
        auth_header
      )
    );
    result := result || '{"event_dispatcher": "registered"}'::jsonb;
  ELSE
    result := result || '{"event_dispatcher": "already_exists"}'::jsonb;
  END IF;

  -- Cleanup: remove duplicate heartbeat-12h if it exists
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'flowpilot-heartbeat-12h') THEN
    PERFORM cron.unschedule('flowpilot-heartbeat-12h');
    result := result || '{"heartbeat_12h_duplicate": "removed"}'::jsonb;
  END IF;

  RETURN result;
END;
$function$;

ALTER FUNCTION public.register_flowpilot_cron(text, text) OWNER TO postgres;

COMMENT ON FUNCTION public.register_flowpilot_cron(text, text) IS
  'Runtime cron registrar: schedules the 7 platform jobs (heartbeat, automation-dispatcher, publish-scheduled-pages, flowpilot-learn, daily-briefing, instance-health, event-dispatcher) against THIS instance''s url/anon key. Create-only-if-absent, so it is safe to re-run on every bootstrap — which is how a newly added job reaches instances already past the migration ledger.';
