-- The Gmail reconcile poll has never delivered a message. It sends the wrong key.
--
-- Measured on dev 2026-08-02: 72 responses of 401 Unauthorized in six hours, one
-- every five minutes, matching the gmail-reconcile schedule exactly — while
-- cron.job_run_details reported 36 SUCCEEDED runs over the same window. pg_cron
-- grades the SQL, not the HTTP call underneath it, so a poll installed as the
-- fallback for Composio's 12-hour push gaps was dead from the first tick and
-- looked healthy the whole time.
--
-- Cause: the fleet runs TWO anon key formats at once. On dev, 5 cron jobs carry
-- the old `ey…` JWT and 8 carry the new `sb_…` publishable key. The vault has no
-- SUPABASE_ANON_KEY at all (verified: 0 rows), so the fallback below always runs
-- — and it was anchored to the old format:
--
--     substring(command from 'Bearer (ey[A-Za-z0-9_.\-]+)')
--
-- It therefore lifted an `ey…` key from one of the five, while composio-proxy
-- compares the caller against Deno.env.get('SUPABASE_ANON_KEY'), which on a
-- current project is the `sb_…` one. Wrong key in, no match, fall through to
-- getUser(), 401.
--
-- Two changes:
--
-- 1. The fallback accepts both formats and PREFERS `sb_`, because that is what
--    the edge runtime holds. Preferring rather than merely accepting matters:
--    with both present, picking either at random reintroduces the same failure
--    on half of instances.
--
-- 2. The return value now names the key format and where it came from. pg_net's
--    response body is the only place a 401 was visible, and nothing reads it.
--    cron.job_run_details.return_message is read — so the next time these two
--    sides disagree, one query answers it instead of an evening.

CREATE OR REPLACE FUNCTION public.run_gmail_reconcile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_enabled boolean;
  v_key_source text := 'vault';
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.inbound_email_accounts
    WHERE enabled = true AND composio_account_id IS NOT NULL
  ) INTO v_enabled;

  IF NOT v_enabled THEN
    RETURN jsonb_build_object('skipped', 'no enabled composio mailbox');
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_ANON_KEY' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL; v_key := NULL;
  END;

  IF v_url IS NULL THEN
    SELECT substring(command from 'https://[a-z0-9]+\.supabase\.co')
      INTO v_url
      FROM cron.job
     WHERE command LIKE '%functions/v1/%'
     LIMIT 1;
  END IF;

  -- New publishable format first: it is what SUPABASE_ANON_KEY resolves to
  -- inside an edge function, and therefore what composio-proxy compares against.
  IF v_key IS NULL THEN
    v_key_source := 'cron:sb_';
    SELECT substring(command from 'Bearer (sb_[A-Za-z0-9_\-]+)')
      INTO v_key
      FROM cron.job
     WHERE command LIKE '%Bearer sb\_%'
     LIMIT 1;
  END IF;

  -- Legacy JWT only if no sb_ key exists anywhere — an older instance that has
  -- not been migrated will still have a matching env var on its side.
  IF v_key IS NULL THEN
    v_key_source := 'cron:ey';
    SELECT substring(command from 'Bearer (ey[A-Za-z0-9_.\-]+)')
      INTO v_key
      FROM cron.job
     WHERE command LIKE '%Bearer ey%'
     LIMIT 1;
  END IF;

  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('skipped', 'no supabase url/key available for reconcile');
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/composio-proxy',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object(
      'action', 'gmail_reconcile',
      'entity_id', 'default',
      -- Sent for older deployments that still read them. A current composio-proxy
      -- pins the poll's shape server-side for an anon caller and ignores these,
      -- because that key is public and a caller-chosen query turns the response
      -- count into a search oracle over the mailbox.
      'params', jsonb_build_object('max_results', 15, 'query', 'in:inbox newer_than:1d')
    ),
    timeout_milliseconds := 30000
  );

  -- Dispatched is NOT delivered: net.http_post is fire-and-forget, so this says
  -- the request left, never that it was accepted. Naming the key and its source
  -- is what makes the difference diagnosable from the run log.
  RETURN jsonb_build_object(
    'dispatched', true,
    'key_source', v_key_source,
    'key_format', CASE WHEN v_key LIKE 'sb\_%' THEN 'sb_' ELSE 'ey' END,
    'at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.run_gmail_reconcile() IS
  'Polls the company mailbox via composio-proxy as a fallback for Composio push, '
  'which arrives in bursts with observed gaps up to 12h. Returns key_source and '
  'key_format because the anon key exists in two formats across the fleet and a '
  'mismatch surfaces only as a 401 in net._http_response, which nothing reads.';
