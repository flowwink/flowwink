-- The Visitor behavior panel was empty for every form lead, ever.
--
-- The machinery existed: stitch_visitor_to_lead backfills page_views.lead_id
-- and records the identity, and the panel reads exactly that. But only the
-- CHAT path ever called it. The form path never has — not the old client
-- insert (leads has utm columns, no visitor column, so the visitor id it
-- collected went nowhere) and not the new RPC. And trg_lead_auto_stitch
-- existed as a FUNCTION with no CREATE TRIGGER binding it to anything, so the
-- chat-session fallback never fired either. page_views.lead_id: 0 rows on a
-- site with 121 tracked views in a day.
--
-- Three closures:

-- ─── 1. The form path stitches ──────────────────────────────────────────────
-- New signature adds p_visitor_id. The old 8-arg signature must be DROPPED,
-- not just replaced: CREATE OR REPLACE with an extra defaulted parameter
-- creates an OVERLOAD, and PostgREST refuses ambiguous rpc names — every
-- deployed client would start failing.
DROP FUNCTION IF EXISTS public.ingest_form_lead(text, text, text, text, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.ingest_form_lead(
  p_email text,
  p_name text DEFAULT NULL,
  p_company text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_form_name text DEFAULT NULL,
  p_source_id text DEFAULT NULL,
  p_page_id text DEFAULT NULL,
  p_form_data jsonb DEFAULT '{}'::jsonb,
  p_visitor_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      updated_at = now()
    WHERE id = v_lead_id;

    IF to_regclass('public.lead_activities') IS NOT NULL THEN
      INSERT INTO public.lead_activities (lead_id, type, metadata)
      VALUES (v_lead_id, 'form_submit',
              jsonb_build_object('form_name', p_form_name, 'page_id', p_page_id,
                                 'form_data', p_form_data));
    END IF;
  ELSE
    INSERT INTO public.leads (email, name, phone, source, source_id, status, score)
    VALUES (v_email,
            NULLIF(trim(p_name), ''),
            NULLIF(trim(p_phone), ''),
            'form', p_source_id, 'lead', 10)
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
$$;

REVOKE ALL ON FUNCTION public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text)
  TO anon, authenticated, service_role;

-- ─── 2. Bind the auto-stitch trigger that never was ─────────────────────────
-- The function stitches chat sessions whose customer_email matches a new lead.
DROP TRIGGER IF EXISTS trg_lead_auto_stitch ON public.leads;
CREATE TRIGGER trg_lead_auto_stitch
  AFTER INSERT ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.trg_lead_auto_stitch();
