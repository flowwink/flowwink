-- Svante-fynd 2026-08-17 (kväll #3): formulärinkorgen kan inte svara på
-- "är det här omhändertaget?". Leadet föds av ingest-rälsen men inskicket får
-- aldrig veta det, och inskick som INTE blir lead har inget klar-läge alls.
--
-- Design (proveniens före flagga):
--   * lead_id — stämplas av ingest_form_lead när leadet skapas/dedupas.
--     Ett inskick med lead ÄR omhändertaget, och chippen i UI:t visar VAD som
--     hände, inte bara att något hände.
--   * handled_at/handled_by — en enda manuell "Done" för resten. Ingen
--     statusmaskin, inga mellanlägen.
-- Flaggan är DATA, så en operator kan svepa oomhändertagna inskick.

ALTER TABLE public.form_submissions
  ADD COLUMN IF NOT EXISTS lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS handled_at timestamptz,
  ADD COLUMN IF NOT EXISTS handled_by uuid;

-- Klar-markering följer matrisen, som läsning och radering redan gör.
DROP POLICY IF EXISTS "forms module updates form_submissions" ON public.form_submissions;
CREATE POLICY "forms module updates form_submissions" ON public.form_submissions
  FOR UPDATE USING (public.can_access_module(auth.uid(), 'forms'))
  WITH CHECK (public.can_access_module(auth.uid(), 'forms'));

-- ingest_form_lead får p_submission_id (defaultad — gamla anropare fortsätter
-- fungera) och stämplar inskickets lead_id server-side. RETURNS void består:
-- en utomstående ska inte kunna sondera vilka adresser som finns i CRM:et.
-- Gamla signaturen droppas explicit så PostgREST inte ser två överlagringar.
DROP FUNCTION IF EXISTS public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.ingest_form_lead(p_email text, p_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_form_name text DEFAULT NULL::text, p_source_id text DEFAULT NULL::text, p_page_id text DEFAULT NULL::text, p_form_data jsonb DEFAULT '{}'::jsonb, p_visitor_id text DEFAULT NULL::text, p_first_utm_source text DEFAULT NULL::text, p_first_utm_medium text DEFAULT NULL::text, p_first_utm_campaign text DEFAULT NULL::text, p_last_utm_source text DEFAULT NULL::text, p_last_utm_medium text DEFAULT NULL::text, p_last_utm_campaign text DEFAULT NULL::text, p_submission_id uuid DEFAULT NULL::uuid)
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

  -- Provenance back onto the submission: the inbox row can now answer
  -- "what happened to this?" with a link instead of a guess.
  IF p_submission_id IS NOT NULL THEN
    UPDATE public.form_submissions
       SET lead_id = v_lead_id
     WHERE id = p_submission_id AND lead_id IS NULL;
  END IF;

  -- Identify the browser behind the submission: backfills page_views.lead_id
  -- so the CRM's Visitor behavior panel shows the journey that led here.
  IF p_visitor_id IS NOT NULL AND trim(p_visitor_id) <> '' THEN
    PERFORM public.stitch_visitor_to_lead(trim(p_visitor_id), v_lead_id, 'form_submit');
  END IF;
END;
$function$;
