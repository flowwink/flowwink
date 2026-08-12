
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.trigger_score_visitor_intent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- SANITISED 2026-08-12. This file originally hardcoded the DEVELOPMENT
  -- project's URL and anon key here, so every instance that replayed it POSTed
  -- its customers' identified leads to our dev project — and scored none of
  -- them, since the lead_id meant nothing there. Superseded on live instances by
  -- 20260812180000; rewritten here so a fresh replay never creates the bad
  -- version even briefly, and so the key stops shipping in a public repo.
  --
  -- SQL cannot know which instance it is running on. The identity is borrowed at
  -- runtime from the knowledge-indexer cron job, which each instance registers
  -- with its own host and key (the edge runtime is the one thing that knows).
  -- No template yet → post nowhere. Sending nowhere beats sending to us.
  SELECT command INTO v_template FROM cron.job WHERE jobname = 'knowledge-indexer';
  IF v_template IS NULL THEN
    RETURN NEW;
  END IF;

  v_url := substring(v_template from 'https://[^'']+/functions/v1/') || 'score-visitor-intent';
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
  -- Never block a lead insert if the async call fails
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leads_score_on_identify ON public.leads;
CREATE TRIGGER leads_score_on_identify
AFTER INSERT OR UPDATE OF email, phone ON public.leads
FOR EACH ROW
EXECUTE FUNCTION public.trigger_score_visitor_intent();
