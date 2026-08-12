CREATE OR REPLACE FUNCTION public._platform_base_url()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, vault
AS $$
  SELECT rtrim(decrypted_secret, '/')
  FROM vault.decrypted_secrets
  WHERE name IN ('SUPABASE_URL', 'PROJECT_URL')
    AND decrypted_secret ~ '^https?://'
  ORDER BY (name = 'SUPABASE_URL') DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._platform_base_url() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._platform_base_url() TO service_role;

CREATE OR REPLACE FUNCTION public.ensure_platform_secret(p_name text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_id uuid;
  v_current text;
BEGIN
  IF auth.role() <> 'service_role' AND NOT has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only the service role or an admin can set platform secrets';
  END IF;
  IF p_name IS NULL OR trim(p_name) = '' OR p_value IS NULL OR trim(p_value) = '' THEN
    RETURN jsonb_build_object('error', 'p_name and p_value are both required');
  END IF;
  SELECT id, decrypted_secret INTO v_id, v_current
  FROM vault.decrypted_secrets WHERE name = p_name LIMIT 1;
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(p_value, p_name, 'Platform config, written by the edge layer');
    RETURN jsonb_build_object('name', p_name, 'action', 'created');
  ELSIF v_current IS DISTINCT FROM p_value THEN
    PERFORM vault.update_secret(v_id, p_value);
    RETURN jsonb_build_object('name', p_name, 'action', 'updated');
  END IF;
  RETURN jsonb_build_object('name', p_name, 'action', 'unchanged');
END;
$$;
REVOKE ALL ON FUNCTION public.ensure_platform_secret(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_platform_secret(text, text) TO service_role;

CREATE TABLE IF NOT EXISTS public.platform_dispatch_failures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name text,
  signal_name text,
  entity_type text,
  entity_id text,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.platform_dispatch_failures TO authenticated;
GRANT ALL ON public.platform_dispatch_failures TO service_role;
CREATE INDEX IF NOT EXISTS idx_platform_dispatch_failures_created
  ON public.platform_dispatch_failures (created_at DESC);
ALTER TABLE public.platform_dispatch_failures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read dispatch failures" ON public.platform_dispatch_failures;
CREATE POLICY "Admins read dispatch failures" ON public.platform_dispatch_failures
  FOR SELECT USING (has_role(auth.uid(), 'admin'));

DROP FUNCTION IF EXISTS public.dispatch_automation_event(text, text, jsonb, text, text);
CREATE OR REPLACE FUNCTION public.dispatch_automation_event(
  event_name text,
  signal_name text,
  payload jsonb,
  entity_type text DEFAULT NULL,
  entity_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_url text;
  v_key text;
  v_headers jsonb;
BEGIN
  v_url := public._platform_base_url();
  IF v_url IS NULL THEN
    INSERT INTO public.platform_dispatch_failures
      (event_name, signal_name, entity_type, entity_id, reason)
    VALUES (event_name, signal_name, entity_type, entity_id,
            'No platform base URL — vault has no SUPABASE_URL. The edge layer seeds it via ensure_platform_secret(); check that automation-dispatcher is deployed and running on cron.');
    RAISE WARNING 'dispatch_automation_event: no platform base URL configured';
    RETURN;
  END IF;
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets
  WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;
  v_headers := jsonb_build_object('Content-Type', 'application/json');
  IF v_key IS NOT NULL AND trim(v_key) <> '' THEN
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_key);
  END IF;
  IF event_name IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/send-webhook',
      headers := v_headers,
      body := jsonb_build_object('event', event_name, 'data', payload)
    );
  END IF;
  IF signal_name IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/signal-dispatcher',
      headers := v_headers,
      body := jsonb_build_object(
        'signal', signal_name,
        'data', payload,
        'context', jsonb_build_object(
          'entity_type', COALESCE(entity_type, 'unknown'),
          'entity_id', COALESCE(entity_id, '')
        )
      )
    );
  END IF;
END;
$$;

-- REPLAY GUARD (2026-08-13): this is an EARLY definition of get_public_contract.
-- Replaying it onto an instance that already carries a LATER one (different
-- OUT columns, e.g. the appendices version) is 42P13 at best and a silent
-- downgrade at worst — found when the GitHub-integration deploy replayed
-- ledger holes on the fleet. Skip when the function exists; from zero the
-- normal order creates here and upgrades later.
DO $guard$ BEGIN
  IF to_regprocedure('public.get_public_contract(text)') IS NULL THEN
    EXECUTE $create$
CREATE OR REPLACE FUNCTION public.get_public_contract(p_token text)
RETURNS TABLE (
  id uuid,
  title text,
  counterparty_name text,
  counterparty_email text,
  status public.contract_status,
  body_markdown text,
  signed_at timestamptz,
  version integer,
  currency text,
  value_cents bigint,
  start_date date,
  end_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.title, c.counterparty_name, c.counterparty_email, c.status,
         c.body_markdown, c.signed_at, c.version, c.currency, c.value_cents,
         c.start_date, c.end_date
  FROM public.contracts c
  WHERE length(coalesce(trim(p_token), '')) >= 16
    AND c.accept_token = trim(p_token)
  LIMIT 1;
$$
    $create$;
  END IF;
END $guard$;
GRANT EXECUTE ON FUNCTION public.get_public_contract(text) TO anon, authenticated, service_role;

ALTER TABLE public.contract_templates
  ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.get_public_terms()
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  contract_type public.contract_type,
  language text,
  body_markdown text,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id, t.name, t.description, t.contract_type, t.language,
         t.body_markdown, t.updated_at
  FROM public.contract_templates t
  WHERE t.is_public AND t.is_active
  ORDER BY
    (t.name NOT ILIKE 'Allmänna%'), t.name;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_terms() TO anon, authenticated, service_role;