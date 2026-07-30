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

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_ANON_KEY' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL; v_key := NULL;
  END;

  -- Fallback to whatever an existing cron job already uses (same project URL + anon key).
  IF v_url IS NULL THEN
    SELECT substring(command from 'https://[a-z0-9]+\.supabase\.co')
      INTO v_url
      FROM cron.job
     WHERE command LIKE '%functions/v1/%'
     LIMIT 1;
  END IF;
  IF v_key IS NULL THEN
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
      'params', jsonb_build_object('max_results', 15, 'query', 'in:inbox newer_than:1d')
    ),
    timeout_milliseconds := 30000
  );

  RETURN jsonb_build_object('dispatched', true, 'at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.run_gmail_reconcile() FROM public;
GRANT EXECUTE ON FUNCTION public.run_gmail_reconcile() TO service_role;