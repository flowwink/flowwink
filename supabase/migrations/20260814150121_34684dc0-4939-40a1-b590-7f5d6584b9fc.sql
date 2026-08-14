CREATE OR REPLACE FUNCTION "public"."seed_demo_quotes"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count int := 0;
  v_items_count int := 0;
  v_qid uuid;
  v_qnum text;
  v_lead RECORD;
  v_product RECORD;
  v_unit_price bigint;
  v_qty int;
  v_subtotal bigint;
  v_tax bigint;
  v_status text;
  v_statuses text[] := ARRAY['draft','sent','viewed','accepted','rejected','expired'];
  v_titles text[] := ARRAY[
    'Draft quote — ask your agent to finish and send it',
    'Sent quote — awaiting customer response',
    'Viewed quote — the customer opened it; time for a follow-up',
    'Accepted quote — ready to convert to an invoice',
    'Rejected quote — capture the reason and learn from it',
    'Expired quote — valid_until has passed; ask your agent to reissue it'
  ];
  v_idx int := 1;
BEGIN
  FOR v_lead IN
    SELECT l.id, l.name, l.email, c.name AS company_name
    FROM leads l
    LEFT JOIN companies c ON c.id = l.company_id
    WHERE l.email IS NOT NULL
    ORDER BY l.created_at DESC
    LIMIT 6
  LOOP
    v_status := v_statuses[((v_count) % array_length(v_statuses,1)) + 1];
    v_qnum := 'DEMO-Q-'||to_char(now(),'YYYY')||'-'||lpad((v_count+1)::text,4,'0')||'-'||substring(p_run_id::text,1,4);

    INSERT INTO quotes (
      quote_number, status, lead_id,
      customer_name, customer_email, customer_company,
      title, intro_text, terms_text,
      subtotal_cents, tax_cents, total_cents, currency,
      valid_until, notes,
      sent_at, viewed_at, accepted_at, rejected_at
    ) VALUES (
      v_qnum, v_status::quote_status, v_lead.id,
      v_lead.name, v_lead.email, v_lead.company_name,
      v_titles[((v_count) % array_length(v_titles,1)) + 1],
      'Thank you for the opportunity to quote on this engagement.',
      'Payment terms: 30 days net. Quote valid for 30 days.',
      0, 0, 0, 'SEK',
      CASE WHEN v_status = 'expired' THEN (now() - interval '5 days')::date ELSE (now() + interval '30 days')::date END,
      'demo:'||p_scenario,
      CASE WHEN v_status IN ('sent','viewed','accepted','rejected','expired') THEN now() - interval '10 days' ELSE NULL END,
      CASE WHEN v_status IN ('viewed','accepted','rejected') THEN now() - interval '3 days' ELSE NULL END,
      CASE WHEN v_status = 'accepted' THEN now() - interval '2 days' ELSE NULL END,
      CASE WHEN v_status = 'rejected' THEN now() - interval '1 day' ELSE NULL END
    )
    RETURNING id INTO v_qid;
    PERFORM _demo_register_row(p_run_id,'quotes',v_qid);
    v_count := v_count + 1;

    v_idx := 0;
    FOR v_product IN
      SELECT id, name, price_cents FROM products WHERE is_active = true ORDER BY random() LIMIT 3
    LOOP
      v_qty := 1 + floor(random()*4)::int;
      v_unit_price := COALESCE(v_product.price_cents, 150000);
      v_subtotal := v_qty * v_unit_price;
      v_tax := (v_subtotal * 0.25)::bigint;

      INSERT INTO quote_items (
        quote_id, position, description, quantity, unit, unit_price_cents,
        tax_rate_pct, line_subtotal_cents, line_tax_cents, line_total_cents, product_id
      ) VALUES (
        v_qid, v_idx, v_product.name, v_qty, 'st', v_unit_price,
        25.00, v_subtotal, v_tax, v_subtotal + v_tax, v_product.id
      );
      v_idx := v_idx + 1;
      v_items_count := v_items_count + 1;
    END LOOP;

    IF v_idx = 0 THEN
      v_unit_price := 75000 + floor(random()*30)::int * 5000;
      v_qty := 1 + floor(random()*3)::int;
      v_subtotal := v_qty * v_unit_price;
      v_tax := (v_subtotal * 0.25)::bigint;
      INSERT INTO quote_items (
        quote_id, position, description, quantity, unit, unit_price_cents,
        tax_rate_pct, line_subtotal_cents, line_tax_cents, line_total_cents
      ) VALUES (
        v_qid, 0, 'Consulting services', v_qty, 'h', v_unit_price,
        25.00, v_subtotal, v_tax, v_subtotal + v_tax
      );
      v_items_count := v_items_count + 1;
    END IF;

    UPDATE quotes SET
      subtotal_cents = COALESCE((SELECT SUM(line_subtotal_cents) FROM quote_items WHERE quote_id = v_qid), 0),
      tax_cents = COALESCE((SELECT SUM(line_tax_cents) FROM quote_items WHERE quote_id = v_qid), 0),
      total_cents = COALESCE((SELECT SUM(line_total_cents) FROM quote_items WHERE quote_id = v_qid), 0)
    WHERE id = v_qid;
  END LOOP;

  RETURN jsonb_build_object('quotes', v_count, 'line_items', v_items_count, 'skipped_reason',
    CASE WHEN v_count = 0 THEN 'no leads found — seed CRM first' ELSE NULL END);
END;
$$;


ALTER FUNCTION "public"."seed_demo_quotes"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_reconciliation"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count int := 0;
  v_id uuid;
  v_bank_id uuid;
  r RECORD;
  i int := 1;
BEGIN
  SELECT id INTO v_bank_id FROM bank_accounts WHERE archived = false ORDER BY is_default DESC, created_at LIMIT 1;
  IF v_bank_id IS NULL THEN
    INSERT INTO bank_accounts (name, account_number, currency, gl_account, is_default)
    VALUES ('Demo Operating Account', 'SE45 5000 0000 0583 9825 7466', 'SEK', '1930', true)
    RETURNING id INTO v_bank_id;
    PERFORM _demo_register_row(p_run_id, 'bank_accounts', v_bank_id);
  END IF;

  FOR r IN SELECT * FROM (VALUES
    ('Globex Inc',       'INV-2025-0142', 1500000, CURRENT_DATE - 14, 'matched',   'Matched inflow — fully reconciled against a customer invoice'),
    ('AWS EMEA SARL',    'AWS-INV-9381',  -348000, CURRENT_DATE - 5,  'matched',   'Matched outflow — negative amount, reconciled against a vendor bill'),
    ('Pied Piper',       'INV-2025-0156',  125000, CURRENT_DATE - 6,  'partial',   'Partial match — half reconciled; ask your agent to find the rest'),
    ('Unknown transfer', 'TXN-998877',      85000, CURRENT_DATE - 1,  'unmatched', 'Unmatched inflow — this is the row the reconciliation workflow acts on'),
    ('Bank fee',         'FEE-202511',      -7500, CURRENT_DATE - 3,  'unmatched', 'Unmatched outflow — small bank fee waiting to be booked'),
    ('Own account',      'INTTRF-4411',     50000, CURRENT_DATE - 2,  'ignored',   'Ignored — internal transfer, deliberately excluded from matching')
  ) AS t(party, ref_, amount, when_, status_, note_) LOOP
    INSERT INTO bank_transactions (
      bank_account_id, source, external_id, transaction_date, amount_cents,
      currency, counterparty, reference, description, status, matched_amount_cents
    ) VALUES (
      v_bank_id, 'csv', 'demo-'||p_run_id::text||'-'||i, r.when_, r.amount,
      'SEK', r.party, r.ref_, r.note_, r.status_,
      CASE r.status_ WHEN 'matched' THEN abs(r.amount) WHEN 'partial' THEN abs(r.amount)/2 ELSE 0 END
    ) RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'bank_transactions', v_id);
    v_count := v_count + 1;
    i := i + 1;
  END LOOP;
  RETURN jsonb_build_object('bank_transactions', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_reconciliation"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_recruitment"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Published: Senior Backend Engineer ('||v_suffix||')', 'senior-backend-'||v_suffix,  'Engineering', 'Stockholm', 'hybrid', 'full_time'::employment_kind,  'published'::job_posting_status, 650000, 850000, 'Status published: live on the public careers page and accepting applications.',                    true,  false),
    ('Draft: Marketing Intern ('||v_suffix||')',            'marketing-intern-'||v_suffix,'Marketing',   'Stockholm', 'hybrid', 'internship'::employment_kind, 'draft'::job_posting_status,     180000, 220000, 'Status draft: not yet visible — ask your agent to finish this posting and publish it.',            false, false),
    ('Closed: Interim Data Engineer ('||v_suffix||')',      'interim-data-'||v_suffix,    'Engineering', 'Remote EU', 'remote', 'contract'::employment_kind,   'closed'::job_posting_status,    700000, 900000, 'Status closed: position filled — closed_at marks when applications stopped.',                      true,  true),
    ('Archived: Office Coordinator ('||v_suffix||')',       'office-coord-'||v_suffix,    'Operations',  'Göteborg',  'onsite', 'part_time'::employment_kind,  'archived'::job_posting_status,  240000, 300000, 'Status archived: hidden everywhere but kept for history and reporting.',                           true,  true)
  ) AS t(title,slug,dept,loc,remote,etype,stat,smin,smax,descr,pub,closed) LOOP
    INSERT INTO public.job_postings(title,slug,department,location,remote_policy,employment_type,status,salary_min_cents,salary_max_cents,currency,description,requirements,published_at,closed_at)
    VALUES (r.title,r.slug,r.dept,r.loc,r.remote,r.etype,r.stat,r.smin*100,r.smax*100,'SEK',
      r.descr,
      'Strong fundamentals, collaborative mindset, fluent in English.',
      CASE WHEN r.pub THEN now() - interval '30 days' ELSE NULL END,
      CASE WHEN r.closed THEN now() - interval '5 days' ELSE NULL END)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'job_postings',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('job_postings', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_recruitment"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_sla"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_pols int := 0;
  v_viols int := 0;
  v_id uuid;
  v_policy_id uuid;
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Urgent tickets: first response 1h', 'Priority-filtered policy — applies only to urgent tickets.',                                      'ticket', 'first_response',  60,  'urgent', true),
    ('All tickets: resolve within 5 days','Resolution SLA across all priorities.',                                                           'ticket', 'resolution',    7200, 'all',    true),
    ('New leads: first contact in 24h',   'Sales follow-up SLA on leads.',                                                                   'lead',   'first_contact', 1440, 'all',    true),
    ('Quotes: follow up within 3 days',   'Disabled policy (enabled = false) — not monitored. Ask your agent to enable it when ready.',      'quote',  'follow_up',     4320, 'all',    false)
  ) AS t(name_, desc_, entity, metric_, mins, prio, enabled_) LOOP
    INSERT INTO sla_policies (name, description, entity_type, metric, threshold_minutes, priority, enabled)
    VALUES (r.name_, r.desc_, r.entity, r.metric_, r.mins, r.prio, r.enabled_)
    RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'sla_policies', v_id);
    v_pols := v_pols + 1;
  END LOOP;

  SELECT id INTO v_policy_id FROM sla_policies WHERE entity_type='ticket' AND metric='first_response' ORDER BY created_at DESC LIMIT 1;
  IF v_policy_id IS NOT NULL THEN
    FOR r IN SELECT * FROM (VALUES
      ('ticket', 'first_response',  60,   75, 'warning',  NULL::timestamptz,       'Open warning — 15 minutes over threshold.'),
      ('ticket', 'first_response',  60,  190, 'critical', NULL::timestamptz,       'Open critical — more than 3x over threshold.'),
      ('ticket', 'resolution',    7200, 8400, 'breach',   NULL::timestamptz,       'Open breach on the resolution SLA — this is what escalations fire on.'),
      ('ticket', 'first_response',  60,   72, 'warning',  now() - interval '2 days','Resolved violation — kept for compliance history.')
    ) AS t(entity, metric_, thresh, actual_, sev, resolved, note_) LOOP
      INSERT INTO sla_violations (policy_id, entity_type, entity_id, metric, threshold_minutes, actual_minutes, severity, resolved_at, notes)
      VALUES (v_policy_id, r.entity, gen_random_uuid()::text, r.metric_, r.thresh, r.actual_, r.sev, r.resolved, r.note_)
      RETURNING id INTO v_id;
      PERFORM _demo_register_row(p_run_id, 'sla_violations', v_id);
      v_viols := v_viols + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('policies', v_pols, 'violations', v_viols);
END $$;


ALTER FUNCTION "public"."seed_demo_sla"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_subscriptions"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count int := 0;
  v_id uuid;
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Active Monthly Demo AB', 'billing@active.example',   'Pro Plan',   'active',   19900,  'month', false, 'Active state — the healthy baseline; renews every period'),
    ('Active Annual Demo AB',  'ap@annual.example',        'Pro Annual', 'active',   199900, 'year',  false, 'Active yearly interval — same state, longer billing period'),
    ('Trialing Demo AB',       'trial@trialing.example',   'Starter',    'trialing', 4900,   'month', false, 'Trialing state — trial_end set; converts to active or churns'),
    ('Past Due Demo AB',       'billing@pastdue.example',  'Pro Plan',   'past_due', 19900,  'month', false, 'Past due state — payment failed. This is the row dunning acts on; ask your agent to follow up'),
    ('Canceled Demo AB',       'billing@canceled.example', 'Pro Plan',   'canceled', 19900,  'month', true,  'Canceled state — canceled_at set; counts as churn'),
    ('Paused Demo AB',         'finance@paused.example',   'Starter',    'paused',   4900,   'month', false, 'Paused state — billing suspended without churning')
  ) AS t(cust, email, plan, status_, amount, interval_, canceled, note_) LOOP
    INSERT INTO subscriptions (
      customer_name, customer_email, product_name, status, unit_amount_cents,
      currency, billing_interval, current_period_start, current_period_end,
      trial_end, canceled_at, provider, metadata
    ) VALUES (
      r.cust, r.email, r.plan, r.status_::subscription_status, r.amount,
      'sek', r.interval_,
      now() - interval '15 days',
      CASE WHEN r.interval_='year' THEN now() + interval '350 days' ELSE now() + interval '15 days' END,
      CASE WHEN r.status_='trialing' THEN now() + interval '7 days' END,
      CASE WHEN r.canceled THEN now() - interval '5 days' END,
      'manual',
      jsonb_build_object('seeded', true, 'demo_note', r.note_)
    ) RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'subscriptions', v_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('subscriptions', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_subscriptions"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";