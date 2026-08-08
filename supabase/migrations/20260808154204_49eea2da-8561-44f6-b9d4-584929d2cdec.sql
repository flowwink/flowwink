CREATE OR REPLACE FUNCTION public._resolve_profile(p_who text)
RETURNS TABLE (user_id uuid, user_email text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id, email FROM public.profiles
  WHERE (p_who ~* '^[0-9a-f]{8}-' AND id = p_who::uuid)
     OR lower(email) = lower(trim(p_who))
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.assign_lead(p_lead text, p_assignee text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lead public.leads%ROWTYPE;
  v_uid uuid; v_email text;
BEGIN
  SELECT * INTO v_lead FROM public.leads
  WHERE (p_lead ~* '^[0-9a-f]{8}-' AND id = p_lead::uuid)
     OR lower(email) = lower(trim(p_lead))
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Lead not found: '||p_lead||'. Pass the lead''s email or id.');
  END IF;
  SELECT user_id, user_email INTO v_uid, v_email FROM public._resolve_profile(p_assignee);
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'No user with email or id '||p_assignee||'. The assignee must be a platform user (Settings → Users).');
  END IF;
  UPDATE public.leads SET assigned_to = v_uid, updated_at = now() WHERE id = v_lead.id;
  RETURN (SELECT jsonb_build_object(
    'lead_id', id, 'lead_email', email, 'lead_name', name,
    'assigned_to', assigned_to, 'assignee_email', v_email)
  FROM public.leads WHERE id = v_lead.id);
END; $$;

CREATE OR REPLACE FUNCTION public.assign_company(p_company text, p_owner text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid; v_name text; v_uid uuid; v_email text;
BEGIN
  SELECT id, name INTO v_id, v_name FROM public.companies
  WHERE (p_company ~* '^[0-9a-f]{8}-' AND id = p_company::uuid)
     OR lower(name) = lower(trim(p_company))
  LIMIT 1;
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Company not found: '||p_company||'. Pass the exact name or id.');
  END IF;
  SELECT user_id, user_email INTO v_uid, v_email FROM public._resolve_profile(p_owner);
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'No user with email or id '||p_owner||'.');
  END IF;
  UPDATE public.companies SET account_owner = v_uid, updated_at = now() WHERE id = v_id;
  RETURN jsonb_build_object('company_id', v_id, 'company_name', v_name,
                            'account_owner', v_uid, 'owner_email', v_email);
END; $$;

CREATE OR REPLACE FUNCTION public.crm_followup_report(p_stale_days integer DEFAULT 14)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'stale_days_threshold', p_stale_days,
    'stale_leads', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'email', l.email, 'name', l.name, 'status', l.status,
        'score', l.score,
        'days_since_activity', (now()::date - l.updated_at::date),
        'assigned_to_email', p.email)
        ORDER BY l.updated_at)
      FROM public.leads l
      LEFT JOIN public.profiles p ON p.id = l.assigned_to
      WHERE l.status = 'lead'
        AND l.updated_at < now() - make_interval(days => p_stale_days)
    ), '[]'::jsonb),
    'unassigned_leads', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', id, 'email', email, 'name', name)
        ORDER BY created_at DESC)
      FROM public.leads WHERE status = 'lead' AND assigned_to IS NULL
    ), '[]'::jsonb),
    'overdue_tasks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'project_id', t.project_id,
        'due_date', t.due_date, 'days_overdue', (now()::date - t.due_date),
        'status', t.status, 'assigned_to_email', p.email)
        ORDER BY t.due_date)
      FROM public.project_tasks t
      LEFT JOIN public.profiles p ON p.id = t.assigned_to
      WHERE t.completed_at IS NULL AND t.status <> 'done'
        AND t.due_date IS NOT NULL AND t.due_date < now()::date
    ), '[]'::jsonb),
    'tasks_without_due_date', COALESCE((
      SELECT count(*) FROM public.project_tasks
      WHERE completed_at IS NULL AND status <> 'done' AND due_date IS NULL
    ), 0)
  );
$$;

REVOKE ALL ON FUNCTION public._resolve_profile(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_lead(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_company(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crm_followup_report(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_lead(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_company(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_followup_report(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._resolve_profile(text) TO service_role;

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
  IF p_visitor_id IS NOT NULL AND trim(p_visitor_id) <> '' THEN
    PERFORM public.stitch_visitor_to_lead(trim(p_visitor_id), v_lead_id, 'form_submit');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ingest_form_lead(text, text, text, text, text, text, text, jsonb, text)
  TO anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_lead_auto_stitch ON public.leads;
CREATE TRIGGER trg_lead_auto_stitch
  AFTER INSERT ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.trg_lead_auto_stitch();