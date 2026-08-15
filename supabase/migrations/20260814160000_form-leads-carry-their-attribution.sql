-- Form leads carry their attribution — the primary path never did.
--
-- Growth audit (2026-08-14): revenue attribution is structurally empty. One of
-- the two broken legs is here — leads.first_/last_utm_* exist and
-- get_attribution_report reads them, but ingest_form_lead (the SECURITY DEFINER
-- RPC that every real form submission goes through) took no UTM parameters at
-- all. The client DOES capture them (src/lib/utm.ts, buildAttributionFields),
-- but only the legacy fallback path stamped them — and that path fails for
-- every anonymous visitor by design since the July security sweep. Net: every
-- form lead on the fleet was born without attribution, and the report
-- truthfully showed nothing.
--
-- First touch is written ONCE (COALESCE — the campaign that earned the visit
-- must not be overwritten by the one they returned through); last touch is
-- always refreshed (that is what "last touch" means).
--
-- The old 9-arg signature is dropped rather than left beside the new one:
-- keeping both would make a 9-arg call ambiguous between two overloads.

DROP FUNCTION IF EXISTS public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.ingest_form_lead(
  p_email text,
  p_name text DEFAULT NULL::text,
  p_company text DEFAULT NULL::text,
  p_phone text DEFAULT NULL::text,
  p_form_name text DEFAULT NULL::text,
  p_source_id text DEFAULT NULL::text,
  p_page_id text DEFAULT NULL::text,
  p_form_data jsonb DEFAULT '{}'::jsonb,
  p_visitor_id text DEFAULT NULL::text,
  p_first_utm_source text DEFAULT NULL::text,
  p_first_utm_medium text DEFAULT NULL::text,
  p_first_utm_campaign text DEFAULT NULL::text,
  p_last_utm_source text DEFAULT NULL::text,
  p_last_utm_medium text DEFAULT NULL::text,
  p_last_utm_campaign text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := lower(trim(p_email));
  v_lead_id uuid;
  v_existing public.leads%ROWTYPE;
BEGIN
  IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RETURN;
  END IF;

  SELECT * INTO v_existing FROM public.leads WHERE lower(email) = v_email LIMIT 1;

  IF FOUND THEN
    v_lead_id := v_existing.id;
    UPDATE public.leads SET
      name  = COALESCE(name,  NULLIF(trim(p_name), '')),
      phone = COALESCE(phone, NULLIF(trim(p_phone), '')),
      -- First touch survives; last touch follows the visitor.
      first_utm_source   = COALESCE(first_utm_source,   NULLIF(trim(p_first_utm_source), '')),
      first_utm_medium   = COALESCE(first_utm_medium,   NULLIF(trim(p_first_utm_medium), '')),
      first_utm_campaign = COALESCE(first_utm_campaign, NULLIF(trim(p_first_utm_campaign), '')),
      last_utm_source    = COALESCE(NULLIF(trim(p_last_utm_source), ''),   last_utm_source),
      last_utm_medium    = COALESCE(NULLIF(trim(p_last_utm_medium), ''),   last_utm_medium),
      last_utm_campaign  = COALESCE(NULLIF(trim(p_last_utm_campaign), ''), last_utm_campaign),
      updated_at = now()
    WHERE id = v_lead_id;

    IF to_regclass('public.lead_activities') IS NOT NULL THEN
      INSERT INTO public.lead_activities (lead_id, type, metadata)
      VALUES (v_lead_id, 'form_submit',
              jsonb_build_object('form_name', p_form_name, 'page_id', p_page_id,
                                 'form_data', p_form_data));
    END IF;
  ELSE
    INSERT INTO public.leads (
      email, name, phone, source, source_id, status, score,
      first_utm_source, first_utm_medium, first_utm_campaign,
      last_utm_source, last_utm_medium, last_utm_campaign
    )
    VALUES (v_email,
            NULLIF(trim(p_name), ''),
            NULLIF(trim(p_phone), ''),
            'form', p_source_id, 'lead', 10,
            NULLIF(trim(p_first_utm_source), ''),
            NULLIF(trim(p_first_utm_medium), ''),
            NULLIF(trim(p_first_utm_campaign), ''),
            NULLIF(trim(p_last_utm_source), ''),
            NULLIF(trim(p_last_utm_medium), ''),
            NULLIF(trim(p_last_utm_campaign), ''))
    RETURNING id INTO v_lead_id;

    IF to_regclass('public.lead_activities') IS NOT NULL THEN
      INSERT INTO public.lead_activities (lead_id, type, metadata)
      VALUES (v_lead_id, 'form_submit',
              jsonb_build_object('form_name', p_form_name, 'page_id', p_page_id,
                                 'company', NULLIF(trim(p_company), ''),
                                 'form_data', p_form_data));
    END IF;
  END IF;

  -- Identify the browser behind the submission: backfills page_views.lead_id
  -- so the CRM's Visitor behavior panel shows the journey that led here.
  IF p_visitor_id IS NOT NULL AND trim(p_visitor_id) <> '' THEN
    PERFORM public.stitch_visitor_to_lead(trim(p_visitor_id), v_lead_id, 'form_submit');
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.ingest_form_lead(
  text, text, text, text, text, text, text, jsonb, text,
  text, text, text, text, text, text
) TO anon, authenticated, service_role;
