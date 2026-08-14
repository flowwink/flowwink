CREATE OR REPLACE FUNCTION "public"."seed_demo_surveys"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('NPS — quarterly relationship survey ('||v_suffix||')', 'nps',  'Active NPS template: a 0-10 score plus one open question. Automations can send it on a schedule.', '[{"id":"q1","type":"nps","prompt":"How likely are you to recommend us?"},{"id":"q2","type":"text","prompt":"What is the main reason for your score?"}]'::jsonb, true),
    ('CSAT — sent after a ticket closes ('||v_suffix||')',   'csat', 'Active CSAT template: satisfaction rating tied to a specific interaction, typically a closed support ticket.', '[{"id":"q1","type":"csat","prompt":"How satisfied are you with the support you received?"},{"id":"q2","type":"text","prompt":"Anything we could do better?"}]'::jsonb, true),
    ('CES — effort score after onboarding ('||v_suffix||')', 'ces',  'Active CES template: measures how easy it was to get something done. Lower effort predicts retention.', '[{"id":"q1","type":"ces","prompt":"How easy was it to get set up?"},{"id":"q2","type":"text","prompt":"What was the hardest step?"}]'::jsonb, true),
    ('Inactive custom survey — ask your agent to revise and activate it ('||v_suffix||')', 'custom', 'Inactive template: not offered anywhere until is_active is set. Custom kind means you define every question yourself.', '[{"id":"q1","type":"text","prompt":"This draft question needs work — what should we ask?"}]'::jsonb, false)
  ) AS t(nm,kind,descr,qs,active) LOOP
    INSERT INTO public.survey_templates(name,kind,description,questions,is_active)
    VALUES (r.nm,r.kind,r.descr,r.qs,r.active) RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'survey_templates',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('survey_templates', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_surveys"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_tickets"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tickets int := 0;
  v_comments int := 0;
  v_id uuid;
  r RECORD;
  v_lead RECORD;
  v_sla interval;
  v_resolved_at timestamptz;
  v_closed_at timestamptz;
  v_lead_id uuid;
  v_company_id uuid;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Checkout fails on card payment',   'Payment page errors out after entering card details. This ticket is brand new and unassigned.',   'new',         'urgent', 'bug',     'Maria Andersson','maria@example.com', 'Internal note: still unassigned — ask your agent to triage this and pick an assignee.', true),
    ('Copy of last month''s invoice',    'How do I download a copy of last month''s invoice? I need it for accounting.',                    'open',        'medium', 'billing', 'Per Svensson','per.s@example.com', 'You can download invoices under Settings → Billing. This ticket stays open until you confirm.', false),
    ('Calendar sync broken since update','Bookings stopped syncing to Google Calendar after last week''s update.',                          'in_progress', 'high',   'bug',     'Tom Karlsson','tom@example.com', 'Reproduced — engineering is investigating the OAuth token refresh. Status: in progress.', false),
    ('Export contacts to CSV',           'Is there a CSV export for contacts? Which fields does it include?',                               'waiting',     'medium', 'question','Eva Holm','eva.h@example.com', 'We asked which fields you need — this ticket is waiting on the customer''s reply.', false),
    ('Dark mode request',                'Would love a dark mode for the dashboard.',                                                       'resolved',    'low',    'feature', 'Lisa Berg','lisa@example.com', 'Added to the roadmap and marked resolved — note the resolved_at timestamp.', false),
    ('Refund for order #1042',           'Wrong size delivered — refund requested and completed.',                                          'closed',      'low',    'other',   'Nils Olsson','nils@example.com', 'Refund completed and ticket closed. Closed tickets carry both resolved_at and closed_at.', false)
  ) AS t(subject, desc_, status, prio, cat, cname, cemail, reply_, is_internal) LOOP

    v_sla := CASE r.prio
      WHEN 'urgent' THEN interval '4 hours'
      WHEN 'high' THEN interval '1 day'
      WHEN 'medium' THEN interval '3 days'
      ELSE interval '7 days'
    END;

    v_resolved_at := CASE WHEN r.status IN ('resolved','closed') THEN now() - interval '1 day' ELSE NULL END;
    v_closed_at := CASE WHEN r.status = 'closed' THEN now() - interval '6 hours' ELSE NULL END;

    SELECT id, company_id INTO v_lead_id, v_company_id
    FROM leads WHERE email IS NOT NULL ORDER BY random() LIMIT 1;

    INSERT INTO tickets (
      subject, description, status, priority, category,
      contact_name, contact_email, source,
      lead_id, company_id,
      sla_deadline, resolved_at, closed_at
    ) VALUES (
      r.subject, r.desc_,
      r.status::ticket_status, r.prio::ticket_priority, r.cat::ticket_category,
      r.cname, r.cemail, 'manual',
      v_lead_id, v_company_id,
      now() + v_sla, v_resolved_at, v_closed_at
    )
    RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'tickets', v_id);
    v_tickets := v_tickets + 1;

    INSERT INTO ticket_comments (ticket_id, content, is_internal, author_type, author_name)
    VALUES (v_id, r.desc_, false, 'customer', r.cname);
    v_comments := v_comments + 1;

    INSERT INTO ticket_comments (ticket_id, content, is_internal, author_type, author_name)
    VALUES (v_id, r.reply_, r.is_internal, 'agent', 'Support Team');
    v_comments := v_comments + 1;
  END LOOP;

  RETURN jsonb_build_object('tickets', v_tickets, 'comments', v_comments);
END;
$$;


ALTER FUNCTION "public"."seed_demo_tickets"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_timesheets"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count int := 0;
  v_id uuid;
  v_proj RECORD;
  v_emp_id uuid;
  r RECORD;
BEGIN
  FOR v_proj IN SELECT id FROM projects ORDER BY created_at DESC LIMIT 1 LOOP
    SELECT id INTO v_emp_id FROM employees ORDER BY random() LIMIT 1;
    FOR r IN SELECT * FROM (VALUES
      (21, 6.0, 'Billable and already invoiced — locked to an invoice (is_invoiced = true).', true,  true),
      (7,  7.5, 'Billable but not yet invoiced — ask your agent to draft the invoice.',       true,  false),
      (5,  3.0, 'Billable, uninvoiced — accumulates toward the next invoice run.',            true,  false),
      (2,  2.0, 'Internal work — not billable (is_billable = false), never invoiced.',        false, false),
      (0,  1.5, 'Logged today — shows up in this week''s timesheet.',                         true,  false)
    ) AS t(days_ago, hrs, descr, billable, invoiced) LOOP
      INSERT INTO time_entries (project_id, employee_id, entry_date, hours, description, is_billable, is_invoiced)
      VALUES (
        v_proj.id, v_emp_id,
        (CURRENT_DATE - r.days_ago)::date,
        r.hrs,
        r.descr,
        r.billable,
        r.invoiced
      ) RETURNING id INTO v_id;
      PERFORM _demo_register_row(p_run_id, 'time_entries', v_id);
      v_count := v_count + 1;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('time_entries', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_timesheets"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_vendors"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Nordic Office Supplies AB ('||v_suffix||')', 'orders+'||v_suffix||'@nordicoffice.se',   '+4684441100', 'https://nordicoffice.se',  'net30','SEK', true,  'Standard SEK vendor on net30 — the typical case'),
    ('CloudHost EU ('||v_suffix||')',              'billing+'||v_suffix||'@cloudhost.eu',     NULL,          'https://cloudhost.eu',     'net15','EUR', true,  'Foreign-currency vendor (EUR) on net15 — exercises FX and shorter terms'),
    ('Stockholm Catering ('||v_suffix||')',        'sales+'||v_suffix||'@sthlmcatering.se',   '+4687123344', NULL,                       'net14','SEK', true,  'Minimal record — no website; ask your agent to enrich this vendor'),
    ('Legal Partners KB ('||v_suffix||')',         'invoice+'||v_suffix||'@legalpartners.se', '+4686677788', 'https://legalpartners.se', 'net30','SEK', true,  'Services vendor — legal fees, typically booked to a different account than goods'),
    ('Retired Printworks ('||v_suffix||')',        'info+'||v_suffix||'@retiredprint.se',     NULL,          NULL,                       'net30','SEK', false, 'Inactive vendor — is_active=false hides it from pickers but keeps history')
  ) AS t(name,email,phone,web,terms,curr,active,notes) LOOP
    INSERT INTO public.vendors(name,email,phone,website,payment_terms,currency,notes,is_active)
    VALUES (r.name,r.email,r.phone,r.web,r.terms,r.curr,r.notes,r.active) RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'vendors',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('vendors', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_vendors"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_webinars"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_webinars int := 0;
  v_regs int := 0;
  v_wid uuid;
  r RECORD;
  v_lead RECORD;
  v_reg_count int;
  i int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Completed webinar — recording attached, follow-ups sent',   'This one already ran. Attendance is tracked per registrant and the recording URL is set — the follow-up automation works from exactly this state.', 'Recap · Attendance · Recording · Follow-up', now() - interval '14 days',       60, 'completed', true),
    ('Published webinar — open for registration',                 'Published webinars are visible on the public site and collect registrations. Reminder emails go out automatically at T-24h and T-1h.',              'Intro · Demo · Q&A',                        now() + interval '7 days',        45, 'published', false),
    ('Live right now — this is what an in-progress webinar looks like', 'Status live means the session has started. Registrants got their T-1h reminder; attendance is confirmed afterwards.',                        'Welcome · Main session · Q&A',              now() - interval '20 minutes',    60, 'live',      false),
    ('Draft webinar — ask your agent to finish the agenda and publish', 'Drafts are internal only: no public page, no registrations. Ask your agent to complete the description and publish it.',                     'TBD — agenda not finished',                 now() + interval '21 days',       45, 'draft',     false),
    ('Cancelled webinar — registrants should get a notice',       'Cancelled after registrations came in. The registrant list is intact — a good test case for asking your agent to draft the cancellation email.',   'Cancelled — was: Intro · Demo · Q&A',       now() + interval '3 days',        45, 'cancelled', false)
  ) AS t(title, desc_, agenda_, when_, dur, status_, has_recording) LOOP

    INSERT INTO webinars (title, description, agenda, date, duration_minutes, max_attendees, platform, meeting_url, recording_url, status)
    VALUES (
      r.title, r.desc_, r.agenda_, r.when_, r.dur, 200,
      'google_meet',
      'https://meet.google.com/demo-'||substring(md5(r.title),1,3)||'-'||substring(md5(r.title),4,4)||'-'||substring(md5(r.title),8,3),
      CASE WHEN r.has_recording THEN 'https://example.com/recordings/'||substring(md5(r.title),1,12)||'.mp4' ELSE NULL END,
      r.status_
    )
    RETURNING id INTO v_wid;
    PERFORM _demo_register_row(p_run_id, 'webinars', v_wid);
    v_webinars := v_webinars + 1;

    v_reg_count := 0;
    FOR v_lead IN
      SELECT id, name, email FROM leads
      WHERE email IS NOT NULL
      ORDER BY random()
      LIMIT (2 + floor(random()*3)::int)
    LOOP
      INSERT INTO webinar_registrations (
        webinar_id, name, email, lead_id, registered_at,
        attended, follow_up_sent,
        reminder_confirm_sent_at, reminder_t24_sent_at, reminder_t1_sent_at, reminder_post_sent_at
      ) VALUES (
        v_wid, v_lead.name, v_lead.email, v_lead.id,
        r.when_ - interval '7 days' + (random() * interval '6 days'),
        CASE WHEN r.status_ = 'completed' THEN random() < 0.65 ELSE false END,
        CASE WHEN r.status_ = 'completed' THEN random() < 0.8 ELSE false END,
        r.when_ - interval '7 days',
        CASE WHEN r.when_ < now() + interval '1 day' THEN r.when_ - interval '24 hours' ELSE NULL END,
        CASE WHEN r.when_ < now() + interval '1 hour' THEN r.when_ - interval '1 hour' ELSE NULL END,
        CASE WHEN r.status_ = 'completed' THEN r.when_ + interval '2 hours' ELSE NULL END
      );
      v_regs := v_regs + 1;
      v_reg_count := v_reg_count + 1;
    END LOOP;

    IF v_reg_count < 3 THEN
      FOR i IN 1..(3 - v_reg_count) LOOP
        INSERT INTO webinar_registrations (webinar_id, name, email, registered_at)
        VALUES (
          v_wid,
          (ARRAY['Alex Demo','Sara Demo','Karl Demo','Mia Demo','Jonas Demo'])[1 + floor(random()*5)::int],
          'demo'||floor(random()*9999)::int||'@example.com',
          r.when_ - interval '5 days'
        );
        v_regs := v_regs + 1;
      END LOOP;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('webinars', v_webinars, 'registrations', v_regs);
END;
$$;


ALTER FUNCTION "public"."seed_demo_webinars"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'seed\_demo\_%'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, authenticated', r.sig);
  END LOOP;
END $revoke$;