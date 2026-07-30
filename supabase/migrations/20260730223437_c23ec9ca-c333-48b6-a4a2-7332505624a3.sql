CREATE OR REPLACE FUNCTION public.run_gmail_reconcile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $$
DECLARE
  v_url text;
  v_key text;
  v_enabled boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.inbound_email_accounts
    WHERE enabled = true AND composio_account_id IS NOT NULL
  ) INTO v_enabled;

  IF NOT v_enabled THEN
    RETURN jsonb_build_object('skipped', 'no enabled composio mailbox');
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;

  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('skipped', 'vault secrets SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set');
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
      'params', jsonb_build_object('max_results', 15, 'query', 'in:inbox newer_than:1d')
    ),
    timeout_milliseconds := 30000
  );

  RETURN jsonb_build_object('dispatched', true, 'at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.run_gmail_reconcile() FROM public;
GRANT EXECUTE ON FUNCTION public.run_gmail_reconcile() TO service_role;

DO $sched$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gmail-reconcile') THEN
      PERFORM cron.alter_job(
        (SELECT jobid FROM cron.job WHERE jobname = 'gmail-reconcile'),
        schedule := '*/5 * * * *',
        command := 'SELECT public.run_gmail_reconcile();'
      );
    ELSE
      PERFORM cron.schedule('gmail-reconcile', '*/5 * * * *', 'SELECT public.run_gmail_reconcile();');
    END IF;
  END IF;
END
$sched$;