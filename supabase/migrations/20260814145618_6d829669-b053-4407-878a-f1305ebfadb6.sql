-- Demo seeds teach the state space — educational fixtures, not marketing.
--
-- Decision (2026-08-12): per-module "Seed demo data" exists to let a fresh
-- operator — human or agent — see the MODULE working in all its states before
-- real content exists. The operator already installed FlowWink; seeds must
-- teach the module, not sell the platform. Two rules, applied to all 30
-- seeders below:
--   1. Cover the state space, not volume: one row per major status
--      (draft/sent/paid/overdue…, open/resolved…, published/draft/scheduled…).
--   2. Rows teach and invite: titles/notes name the state they demonstrate
--      and, where natural, invite the agentic workflow ("This is a draft —
--      ask your agent to finish it").
--
-- Every status value was verified against the actual CHECK constraints and
-- enum types (never guessed); INSERT column lists follow the proven originals
-- with only schema-verified additions. Cleanup registration
-- (_demo_register_row) and run-id suffixing preserved everywhere, so
-- reset/sweep keeps working. Idempotent: CREATE OR REPLACE only.

CREATE OR REPLACE FUNCTION "public"."seed_demo_accounting"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_je int := 0;
  v_jel int := 0;
  v_id uuid;
  r RECORD;
  v_line_id uuid;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Posted expense paid from bank — cloud hosting',                          '6540', 'IT services',       '1930', 'Bank',              348000, CURRENT_DATE - 20, 'posted'),
    ('Posted expense on credit — office supplies (creates a trade payable)',   '6110', 'Office supplies',   '2440', 'Trade payables',    125000, CURRENT_DATE - 25, 'posted'),
    ('Posted revenue on credit — consulting (creates a trade receivable)',     '1510', 'Trade receivables', '3041', 'Consulting revenue',1500000, CURRENT_DATE - 15, 'posted'),
    ('Posted small charge — bank fee (fees post like any other expense)',      '6570', 'Bank fees',         '1930', 'Bank',                7500, CURRENT_DATE - 10, 'posted'),
    ('Draft entry — office rent, not yet posted. Ask your agent to post it.',  '5010', 'Rent',              '1930', 'Bank',             2500000, CURRENT_DATE - 5,  'draft')
  ) AS t(descr, debit_code, debit_name, credit_code, credit_name, amount_cents, when_, status_) LOOP
    INSERT INTO journal_entries (entry_date, description, status, source)
    VALUES (r.when_, r.descr, r.status_, 'manual')
    RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'journal_entries', v_id);
    v_je := v_je + 1;

    INSERT INTO journal_entry_lines (journal_entry_id, account_code, account_name, debit_cents, credit_cents)
    VALUES (v_id, r.debit_code, r.debit_name, r.amount_cents, 0)
    RETURNING id INTO v_line_id;
    PERFORM _demo_register_row(p_run_id, 'journal_entry_lines', v_line_id);

    INSERT INTO journal_entry_lines (journal_entry_id, account_code, account_name, debit_cents, credit_cents)
    VALUES (v_id, r.credit_code, r.credit_name, 0, r.amount_cents)
    RETURNING id INTO v_line_id;
    PERFORM _demo_register_row(p_run_id, 'journal_entry_lines', v_line_id);
    v_jel := v_jel + 2;
  END LOOP;
  RETURN jsonb_build_object('journal_entries', v_je, 'lines', v_jel);
END $$;


ALTER FUNCTION "public"."seed_demo_accounting"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_approvals"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rules int := 0;
  v_reqs int := 0;
  v_id uuid;
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Expense over 5,000 SEK',     'Threshold rule — expenses above this amount require admin approval',        'expense', 500000, 'admin'::app_role),
    ('Purchase order over 25k',    'Threshold rule on a different entity type (purchase orders)',               'purchase_order', 2500000, 'admin'::app_role),
    ('Customer discount approval', 'Rule without an amount threshold — every matching quote needs approval',    'quote', NULL, 'admin'::app_role)
  ) AS t(name_, desc_, entity, thresh, role_) LOOP
    INSERT INTO approval_rules (name, description, entity_type, amount_threshold_cents, currency, required_role)
    VALUES (r.name_, r.desc_, r.entity, r.thresh, 'SEK', r.role_)
    RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'approval_rules', v_id);
    v_rules := v_rules + 1;
  END LOOP;

  FOR r IN SELECT * FROM (VALUES
    ('expense',        'Pending request — travel to Berlin. Ask your agent to review and decide.', 750000, 'pending',   'Pending state — waiting for an approver; this is the row the approval workflow acts on'),
    ('purchase_order', 'Pending request — annual license renewal',                                4800000, 'pending',   'Second pending row — shows the queue with more than one open item'),
    ('quote',          'Approved request — 25% discount for a strategic account',                       0, 'approved',  'Approved state — resolved_at set; the discount may proceed'),
    ('expense',        'Rejected request — client dinner above per-diem limit',                    620000, 'rejected',  'Rejected state — resolved_at set; requester must revise or drop it'),
    ('expense',        'Cancelled request — withdrawn by the requester before a decision',         180000, 'cancelled', 'Cancelled state — closed without an approve/reject decision')
  ) AS t(entity, reason_, amount, status_, ctx_) LOOP
    INSERT INTO approval_requests (entity_type, entity_id, amount_cents, currency, reason, status, required_role, context, resolved_at)
    VALUES (
      r.entity, gen_random_uuid()::text, r.amount, 'SEK', r.reason_,
      r.status_::approval_status, 'admin'::app_role,
      jsonb_build_object('demo_note', r.ctx_),
      CASE WHEN r.status_ IN ('approved','rejected') THEN now() - interval '1 day' END
    ) RETURNING id INTO v_id;
    PERFORM _demo_register_row(p_run_id, 'approval_requests', v_id);
    v_reqs := v_reqs + 1;
  END LOOP;

  RETURN jsonb_build_object('rules', v_rules, 'requests', v_reqs);
END $$;


ALTER FUNCTION "public"."seed_demo_approvals"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_blog"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_post_id uuid;
  v_count int := 0;
  v_posts jsonb := jsonb_build_array(
    jsonb_build_object(
      'title', 'Welcome to your blog — how publishing works',
      'slug', 'demo-welcome-publishing',
      'excerpt', 'A published post. Write, fill in SEO fields, publish — that is the whole flow.',
      'body', 'Every post starts as a draft. When it is ready you publish it, which stamps published_at and makes it visible on the public site. The SEO fields (title, description, keywords) live on the post and feed the page metadata — this post has them filled in as an example. Write posts yourself in the editor, or ask your agent to draft one for you.',
      'state', 'published',
      'image_seed', 'blog-welcome',
      'image_alt', 'An open notebook next to a keyboard'
    ),
    jsonb_build_object(
      'title', 'This is a draft — ask your agent to finish it',
      'slug', 'demo-unfinished-draft',
      'excerpt', 'Drafts are invisible to visitors until published.',
      'body', 'This post is a draft: it has no published_at and does not appear on the public site. Try asking your agent to finish the text, fill in the SEO fields and publish it — that is the normal handoff between you and the agent.',
      'state', 'draft',
      'image_seed', 'blog-draft',
      'image_alt', 'A half-finished sketch on paper'
    ),
    jsonb_build_object(
      'title', 'Scheduled — this post publishes itself in three days',
      'slug', 'demo-scheduled-post',
      'excerpt', 'A draft with scheduled_at set three days ahead.',
      'body', 'This post has scheduled_at set three days from when the demo was seeded. Scheduled posts stay hidden until the scheduler publishes them at the set time. Use this to queue a week of content in one sitting — or ask your agent to plan and schedule a series for you.',
      'state', 'scheduled',
      'image_seed', 'blog-scheduled',
      'image_alt', 'A wall calendar with a circled date'
    )
  );
  v_post jsonb;
BEGIN
  FOR v_post IN SELECT * FROM jsonb_array_elements(v_posts) LOOP
    INSERT INTO public.blog_posts (title, slug, excerpt, content_json, status, published_at, scheduled_at, meta_json, featured_image, featured_image_alt)
    VALUES (
      v_post->>'title',
      v_post->>'slug' || '-' || substring(p_run_id::text, 1, 6),
      v_post->>'excerpt',
      jsonb_build_object(
        'type', 'doc',
        'content', jsonb_build_array(
          jsonb_build_object(
            'type', 'paragraph',
            'content', jsonb_build_array(
              jsonb_build_object('type', 'text', 'text', v_post->>'body')
            )
          )
        )
      ),
      CASE WHEN v_post->>'state' = 'published' THEN 'published'::public.page_status ELSE 'draft'::public.page_status END,
      CASE WHEN v_post->>'state' = 'published' THEN now() ELSE NULL END,
      CASE WHEN v_post->>'state' = 'scheduled' THEN now() + interval '3 days' ELSE NULL END,
      CASE WHEN v_post->>'state' = 'published'
        THEN jsonb_build_object(
          'seoTitle', 'Welcome to your blog — publishing basics',
          'description', 'How drafts, publishing and SEO fields work in the blog module.',
          'keywords', jsonb_build_array('blog', 'publishing', 'seo')
        )
        ELSE '{}'::jsonb END,
      'https://picsum.photos/seed/' || (v_post->>'image_seed') || '/1200/630',
      v_post->>'image_alt'
    )
    RETURNING id INTO v_post_id;

    PERFORM public._demo_register_row(p_run_id, 'blog_posts', v_post_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('blog_posts_created', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_blog"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_bookings"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_svc_count int := 0; v_bk_count int := 0; v_id uuid;
        v_consult uuid; v_strategy uuid; v_legacy uuid; v_suffix text;
        r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  INSERT INTO public.booking_services(name,description,duration_minutes,price_cents,color,sort_order,is_active)
  VALUES ('Discovery call ('||v_suffix||')','Free 30-min intro call — the zero-price service variant.',30,0,'#10b981',1,true) RETURNING id INTO v_consult;
  PERFORM public._demo_register_row(p_run_id,'booking_services',v_consult);

  INSERT INTO public.booking_services(name,description,duration_minutes,price_cents,color,sort_order,is_active)
  VALUES ('Strategy session ('||v_suffix||')','Paid 60-min session — the priced service variant.',60,150000,'#3b82f6',2,true) RETURNING id INTO v_strategy;
  PERFORM public._demo_register_row(p_run_id,'booking_services',v_strategy);

  INSERT INTO public.booking_services(name,description,duration_minutes,price_cents,color,sort_order,is_active)
  VALUES ('Legacy workshop ('||v_suffix||') — inactive','is_active = false: hidden from the public booking page but kept for history.',240,800000,'#8b5cf6',3,false) RETURNING id INTO v_legacy;
  PERFORM public._demo_register_row(p_run_id,'booking_services',v_legacy);
  v_svc_count := 3;

  FOR r IN SELECT * FROM (VALUES
    (v_consult,  'Olof Berg',     'olof@example.com',    NULL,             7, 'pending',   'Status pending: awaiting confirmation — ask your agent to confirm it and send the email.', NULL::timestamptz,          NULL::text),
    (v_strategy, 'Maria Lund',    'maria.l@example.com', '+46707654321',   2, 'confirmed', 'Status confirmed: the reminder automation picks this one up before start_time.',           NULL,                        NULL),
    (v_strategy, 'Karl Wahlberg', 'karl@example.com',    NULL,            -3, 'completed', 'Status completed: a finished appointment — follow-up material for your agent.',            NULL,                        NULL),
    (v_consult,  'Pia Hansson',   'pia@example.com',     NULL,             5, 'cancelled', 'Status cancelled: cancelled_at and cancelled_reason record what happened.',                now() - interval '1 day',    'Customer rescheduled')
  ) AS t(svc,cname,cemail,cphone,day_offset,status,note,cat,creason) LOOP
    INSERT INTO public.bookings(service_id,customer_name,customer_email,customer_phone,start_time,end_time,status,notes,cancelled_at,cancelled_reason)
    VALUES (r.svc, r.cname, r.cemail, r.cphone,
            (current_date + (r.day_offset || ' days')::interval + interval '10 hours')::timestamptz,
            (current_date + (r.day_offset || ' days')::interval + interval '11 hours')::timestamptz,
            r.status, r.note, r.cat, r.creason)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'bookings',v_id);
    v_bk_count := v_bk_count+1;
  END LOOP;
  RETURN jsonb_build_object('booking_services', v_svc_count, 'bookings', v_bk_count);
END $$;


ALTER FUNCTION "public"."seed_demo_bookings"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_companies"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Prospect: Northwind Trading ('||v_suffix||')', 'northwind-'||v_suffix||'.example','Retail',        '11-50',   '+4687123000', 'prospect'::company_lifecycle_stage, 'Lifecycle prospect: not yet a customer — the pipeline starts here.',                                    NULL::timestamptz),
    ('Enrich me: Helios Solar ('||v_suffix||')',     'helios-'||v_suffix||'.example',   NULL,            NULL,      NULL,          'prospect'::company_lifecycle_stage, 'Lifecycle prospect with empty fields: ask your agent to enrich this company from its domain.',           NULL),
    ('Customer: Acme Corp AB ('||v_suffix||')',      'acme-'||v_suffix||'.example',     'Manufacturing', '51-200',  '+4684441000', 'customer'::company_lifecycle_stage, 'Lifecycle customer: customer_since marks when the prospect converted.',                                  now() - interval '400 days'),
    ('Churned: Delta Logistics ('||v_suffix||')',    'delta-'||v_suffix||'.example',    'Logistics',     '201-500', NULL,          'churned'::company_lifecycle_stage,  'Lifecycle churned: a former customer — this is where a win-back play starts.',                           now() - interval '900 days')
  ) AS t(nm,dom,ind,sz,ph,stg,note,since) LOOP
    INSERT INTO public.companies(name,domain,industry,size,phone,website,lifecycle_stage,notes,customer_since)
    VALUES (r.nm,r.dom,r.ind,r.sz,r.ph,'https://'||r.dom,r.stg,r.note,r.since) RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'companies',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('companies', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_companies"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";