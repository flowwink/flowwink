-- Outbound cron follows the instance — the poison chain is cut at both ends.
--
-- FOUND BY THE LOCAL FRESH-REPLAY REHEARSAL (2026-08-12, preparing the sandbox
-- reinstall). On a from-zero replay the poison spreads in three steps:
--
--   1. 20260707022750 schedules `newsletter-dispatch-scheduled` with DEV's
--      hardcoded URL (SQL cannot know its own instance).
--   2. 20260718090000 (the self-heal) runs BEFORE any same-instance job exists,
--      so it no-ops.
--   3. 20260812150000 then bootstraps `knowledge-indexer` by borrowing the
--      envelope from "any job that already calls a function on this instance" —
--      and the only candidate is the poisoned newsletter job. The healer drinks
--      from the well it was meant to clean.
--
-- End state on a fresh install: TWO cron jobs posting at our dev project, and
-- `trigger_score_visitor_intent` deriving its target from one of them. Every
-- existing fleet instance escaped this only because their heartbeat jobs were
-- registered (with true URLs) before today's migrations arrived.
--
-- The cure has two halves. The other half is in 20260707022750 itself, which no
-- longer hardcodes anything (it derives or skips). This half is the RUNTIME
-- anchor: the one party that always knows the instance's true identity is the
-- app — Deno.env in an edge function, VITE_SUPABASE_URL in the browser. Both
-- already call an RPC with that identity:
--
--   • knowledge-indexer (edge) calls register_knowledge_indexer_cron every run
--   • ensurePlatformCron (browser bootstrap, every admin load) calls
--     register_retrieval_cron — WHICH NEVER EXISTED; the caller tolerates its
--     absence, so that anchor has been dangling since it was written
--
-- Both now resolve to the same reconciler:
--
--   1. knowledge-indexer            → registered, or RE-ANCHORED if its host
--                                     is not this instance
--   2. newsletter-dispatch-scheduled→ same
--   3. any other /functions/v1/ job on a foreign host → DEACTIVATED, loudly.
--      Fail closed: a tick that fires nowhere beats a tick that reports our
--      customers' activity to us. Whoever owns that job re-registers it with
--      its own identity the same way these two do.
--
-- Idempotent: converges in one call, second call is a no-op.

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

  -- 1+2: the two platform ticks this function owns. Register when missing,
  -- re-anchor when present but pointing at some other instance.
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

  -- 3: quarantine. Any OTHER function-calling job aimed at a foreign host is,
  -- by definition, a migration-authored URL — no runtime path can produce one.
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

-- The name the browser bootstrap has been calling into the void since the day
-- it was written (module-bootstrap.ts ensurePlatformCron — "absent on older
-- instances", it says, about every instance). Now it lands here, which makes
-- the FIRST ADMIN PAGE LOAD the moment a fresh install gets its knowledge
-- ticks — no edge call, no manual sweep, no catch-22.
CREATE OR REPLACE FUNCTION public.register_retrieval_cron(p_supabase_url text, p_anon_key text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.register_knowledge_indexer_cron(p_supabase_url, p_anon_key);
$$;

GRANT EXECUTE ON FUNCTION public.register_retrieval_cron(text, text) TO authenticated, service_role;
