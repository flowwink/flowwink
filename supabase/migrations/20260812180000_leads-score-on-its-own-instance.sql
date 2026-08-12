-- A customer's leads stop knocking on our door.
--
-- `trigger_score_visitor_intent` (migration 20260704152107) hardcoded the DEV
-- project's URL and anon key into its body:
--
--   v_url  := 'https://<dev-ref>.supabase.co/functions/v1/score-visitor-intent';
--   v_anon := 'eyJ…';   -- dev's anon key, in plain text, in every customer DB
--
-- Every instance that replayed that migration got it. The trigger fires whenever
-- a lead gains an email or a phone number, so on the live fleet each customer's
-- lead flow POSTed to OUR development instance. Confirmed present on two
-- production instances on 2026-08-12.
--
-- The blast radius is narrower than it first looks — the body is `{lead_id}`
-- only, and that UUID does not exist in dev's database, so no personal data ever
-- left the customer and dev could not have scored anything. What did leak is
-- timing and volume: we learned when every customer got a qualified lead. And
-- the feature was dead on arrival everywhere — scoring ran against the wrong
-- database, silently, because the function ends in EXCEPTION WHEN OTHERS.
--
-- Same class as the newsletter cron (20260718090000): a migration cannot know
-- the ref of the instance it will run on, so anything it writes with a URL in it
-- is wrong for every instance but the one it was authored against. The cure is
-- the same too — derive the instance's own identity at RUNTIME from the
-- always-self-referential `knowledge-indexer` cron job, which each instance
-- registers with its own host and its own key.
--
-- Fails CLOSED: if the function cannot work out which instance it is on, it
-- posts nothing. Sending nowhere beats sending to us.
--
-- Idempotent (CREATE OR REPLACE) and forward-dated so managed migrate ledgers
-- do not skip it.

CREATE OR REPLACE FUNCTION public.trigger_score_visitor_intent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_template text;
  v_url      text;
  v_headers  jsonb;
BEGIN
  -- Only fire when a lead has identifiable contact info
  IF NEW.email IS NULL AND NEW.phone IS NULL THEN
    RETURN NEW;
  END IF;

  -- On UPDATE: only fire when email/phone just became present
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.email IS NOT DISTINCT FROM NEW.email)
       AND (OLD.phone IS NOT DISTINCT FROM NEW.phone) THEN
      RETURN NEW;
    END IF;
  END IF;

  -- Borrow this instance's own host and key from a job it registered itself.
  SELECT command INTO v_template FROM cron.job WHERE jobname = 'knowledge-indexer';
  IF v_template IS NULL THEN
    RETURN NEW; -- cannot identify this instance → post nowhere
  END IF;

  v_url := substring(v_template from 'https://[^'']+/functions/v1/')
           || 'score-visitor-intent';
  v_headers := substring(v_template from 'headers := ''(\{[^'']+\})''')::jsonb;
  IF v_url IS NULL OR v_headers IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := v_headers,
    body    := jsonb_build_object('lead_id', NEW.id)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block a lead insert if the async call fails.
  RETURN NEW;
END;
$function$;
