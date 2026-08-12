-- Idempotent: schedule a pg_cron job that POSTs to newsletter/dispatch-scheduled every 5 minutes.
-- The newsletter edge function is deployed --no-verify-jwt; the handler enforces
-- that the Bearer token equals the project anon (or service) key.
-- pg_cron and pg_net are already installed on this project.
-- NB: the Bearer must be the NEW-format publishable key — the deployed edge
-- runtime's SUPABASE_ANON_KEY is the publishable key on this project, so the
-- legacy JWT anon key gets a silent 401 (see project_autonomy_cron_silent_401).

-- SANITISED 2026-08-12. This block originally hardcoded the DEV project's URL
-- and key into the cron command, so every replaying instance dispatched its
-- scheduled newsletters against dev's data (the 2026-07-18 fleet incident). On
-- a FRESH replay it was worse: the poisoned job was the only HTTP job in
-- existence, so 20260812150000's knowledge-indexer bootstrap borrowed its
-- envelope and inherited dev's URL too — the self-heal chain drinking from the
-- poisoned well. Found by the local from-zero rehearsal before the sandbox
-- reinstall.
--
-- SQL cannot know which instance it is on, so this now derives the envelope
-- from an existing same-instance job, or schedules NOTHING. The runtime anchor
-- (register_knowledge_indexer_cron, called from browser bootstrap and the
-- indexer itself with the instance's true identity) registers the job the
-- moment anything with self-knowledge runs. Sending nowhere beats sending to us.
DO $newsletter$
DECLARE
  v_template text;
  v_url      text;
  v_headers  text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'newsletter-dispatch-scheduled') THEN
    PERFORM cron.unschedule('newsletter-dispatch-scheduled');
  END IF;

  SELECT command INTO v_template
    FROM cron.job
   WHERE command LIKE '%/functions/v1/%'
     AND command LIKE '%net.http_post%'
   ORDER BY (jobname = 'flowpilot-heartbeat') DESC,
            (jobname = 'automation-dispatcher-every-minute') DESC,
            jobname
   LIMIT 1;

  IF v_template IS NULL THEN
    RAISE NOTICE 'No same-instance job to derive from — newsletter cron will be registered at runtime.';
    RETURN;
  END IF;

  v_url := substring(v_template from 'url\s*:=\s*''([^'']+)''');
  v_headers := substring(v_template from 'headers\s*:=\s*''([^'']+)''');
  IF v_url IS NULL OR v_headers IS NULL THEN
    RAISE NOTICE 'Could not parse the template job — newsletter cron will be registered at runtime.';
    RETURN;
  END IF;

  v_url := regexp_replace(v_url, '/functions/v1/.*$', '/functions/v1/newsletter/dispatch-scheduled');
  PERFORM cron.schedule(
    'newsletter-dispatch-scheduled',
    '*/5 * * * *',
    format(
      'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source":"cron"}''::jsonb) AS request_id;',
      v_url, v_headers
    )
  );
END $newsletter$;

-- Fresh-replay quiescence (2026-08-11): jobs must not fire into a half-built
-- schema. A from-scratch replay deadlocked (SQLSTATE 40P01) on the very first
-- GitHub-integration run. Every migration that schedules cron jobs at replay
-- time now ends by deactivating ALL jobs; the always-last finalizer
-- (99999999999999) activates everything once the schema is complete. Existing
-- instances never re-run this file (ledger), so they are unaffected.
DO $quiesce$
DECLARE r record;
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    -- cron.alter_job, not UPDATE: on fresh (PG17) projects the postgres role
    -- has no table UPDATE privilege on cron.job — the API function is the
    -- portable path. Verified live on ypkhjjkywgnqhuyiilcz 2026-08-11.
    FOR r IN SELECT jobid FROM cron.job LOOP
      PERFORM cron.alter_job(r.jobid, active => false);
    END LOOP;
  END IF;
END $quiesce$;
