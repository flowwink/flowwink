-- Form submissions stopped becoming leads, silently, as a side effect of a
-- security fix.
--
-- The client path was createLeadFromForm → .insert(...).select().single() on
-- the ANON client. RETURNING requires SELECT permission under RLS, and the
-- July security sweep (correctly) removed public reads from `leads` — so the
-- whole INSERT started failing with an RLS violation. The error is returned,
-- not thrown, and FormBlock never looks at it: the visitor sees "thank you",
-- the submission row exists, and no lead is created. Found on optic when two
-- real submissions produced zero leads while two manual leads sat beside them.
--
-- The dedupe half of that function never worked for visitors at all: the
-- existing-lead lookup runs as anon, RLS filters everything, so every repeat
-- submission would have created a duplicate.
--
-- One SECURITY DEFINER RPC replaces both halves: it can see the table, so it
-- dedupes properly, and it inserts without the caller needing read rights.
-- `leads` stays unreadable to the public — the function returns nothing, not
-- even whether the email already existed, because "is this address in their
-- CRM" is exactly what an outsider should not be able to probe.

CREATE OR REPLACE FUNCTION public.ingest_form_lead(
  p_email text,
  p_name text DEFAULT NULL,
  p_company text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_form_name text DEFAULT NULL,
  p_source_id text DEFAULT NULL,
  p_page_id text DEFAULT NULL,
  p_form_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(p_email));
  v_existing public.leads%ROWTYPE;
BEGIN
  -- A public, unauthenticated surface: validate hard, fail quietly.
  IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RETURN;
  END IF;

  SELECT * INTO v_existing FROM public.leads WHERE lower(email) = v_email LIMIT 1;

  IF FOUND THEN
    -- Progressive enrichment: fill only what is missing, never overwrite.
    UPDATE public.leads SET
      name  = COALESCE(name,  NULLIF(trim(p_name), '')),
      phone = COALESCE(phone, NULLIF(trim(p_phone), '')),
      updated_at = now()
    WHERE id = v_existing.id;

    IF to_regclass('public.lead_activities') IS NOT NULL THEN
      INSERT INTO public.lead_activities (lead_id, type, metadata)
      VALUES (v_existing.id, 'form_submit',
              jsonb_build_object('form_name', p_form_name, 'page_id', p_page_id,
                                 'form_data', p_form_data));
    END IF;
  ELSE
    -- Only columns every instance is known to have. The fleet's leads tables
    -- differ (optic has no `company` text column — company lives on
    -- company_id); a fixed column list must be the common denominator, and the
    -- company name still reaches the CRM inside the activity metadata.
    INSERT INTO public.leads (email, name, phone, source, source_id, status, score)
    VALUES (v_email,
            NULLIF(trim(p_name), ''),
            NULLIF(trim(p_phone), ''),
            'form', p_source_id, 'lead', 10);

    IF to_regclass('public.lead_activities') IS NOT NULL THEN
      INSERT INTO public.lead_activities (lead_id, type, metadata)
      SELECT id, 'form_submit',
             jsonb_build_object('form_name', p_form_name, 'page_id', p_page_id,
                                'company', NULLIF(trim(p_company), ''),
                                'form_data', p_form_data)
      FROM public.leads WHERE lower(email) = v_email LIMIT 1;
    END IF;
  END IF;
END;
$$;

-- The point of the function is that visitors may call it.
GRANT EXECUTE ON FUNCTION public.ingest_form_lead(text, text, text, text, text, text, text, jsonb)
  TO anon, authenticated, service_role;
