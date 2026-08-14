CREATE OR REPLACE FUNCTION "public"."seed_demo_kb"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_cat_id uuid;
  v_art_id uuid;
  v_arts jsonb := jsonb_build_array(
    jsonb_build_object('title', 'Published and featured — visitors and the chat agent see this', 'slug', 'demo-published-featured',
      'question', 'How do knowledge base articles work?',
      'answer', 'Articles are Q&A pairs: a question visitors ask and the answer they get. Published articles appear on the public help pages, and featured ones are pinned at the top. Articles also feed the chat agent, so a good answer here means a good answer in chat.',
      'published', true, 'featured', true, 'in_chat', true),
    jsonb_build_object('title', 'This article is unpublished — ask your agent to review and publish it', 'slug', 'demo-unpublished',
      'question', 'What does unpublished mean for a KB article?',
      'answer', 'Unpublished articles are invisible to visitors and excluded from chat. Use this state to draft answers before they go live. Try asking your agent to review this answer and publish it.',
      'published', false, 'featured', false, 'in_chat', true),
    jsonb_build_object('title', 'Published but kept out of chat — the include_in_chat flag', 'slug', 'demo-not-in-chat',
      'question', 'Can an article be public but excluded from the chat agent?',
      'answer', 'Yes. Each article has an include_in_chat flag. This one is published on the help pages but the chat agent will not use it — handy for legal text or content that reads badly as a chat answer.',
      'published', true, 'featured', false, 'in_chat', false)
  );
  v_art jsonb;
  v_count int := 0;
BEGIN
  INSERT INTO public.kb_categories (name, slug, description, sort_order)
  VALUES ('Getting started with the knowledge base', 'demo-kb-states-' || substring(p_run_id::text, 1, 6),
          'One article per state: published + featured, unpublished draft, and published-but-not-in-chat.', 100)
  RETURNING id INTO v_cat_id;

  PERFORM public._demo_register_row(p_run_id, 'kb_categories', v_cat_id);

  FOR v_art IN SELECT * FROM jsonb_array_elements(v_arts) LOOP
    INSERT INTO public.kb_articles (title, slug, question, answer_text, category_id, is_published, is_featured, include_in_chat)
    VALUES (
      v_art->>'title',
      v_art->>'slug' || '-' || substring(p_run_id::text, 1, 6),
      v_art->>'question',
      v_art->>'answer',
      v_cat_id,
      (v_art->>'published')::boolean,
      (v_art->>'featured')::boolean,
      (v_art->>'in_chat')::boolean
    )
    RETURNING id INTO v_art_id;

    PERFORM public._demo_register_row(p_run_id, 'kb_articles', v_art_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('kb_category_created', 1, 'kb_articles_created', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_kb"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_newsletter"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('confirmed.reader+'||v_suffix||'@example.com', 'Confirmed subscriber — receives every send',            'confirmed',    -60),
    ('new.confirm+'||v_suffix||'@example.com',      'Confirmed recently — the newest cohort',                'confirmed',     -2),
    ('pending.optin+'||v_suffix||'@example.com',    'Pending — has not clicked the double opt-in email yet', 'pending',       -1),
    ('former.reader+'||v_suffix||'@example.com',    'Unsubscribed — kept only for send suppression',         'unsubscribed', -90)
  ) AS t(email,name,status,day_offset) LOOP
    INSERT INTO public.newsletter_subscribers(email,name,status,confirmed_at,unsubscribed_at)
    VALUES (r.email, r.name, r.status,
            CASE WHEN r.status='confirmed' THEN now() + (r.day_offset || ' days')::interval ELSE NULL END,
            CASE WHEN r.status='unsubscribed' THEN now() + (r.day_offset || ' days')::interval ELSE NULL END)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'newsletter_subscribers',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('newsletter_subscribers', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_newsletter"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_pos"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_reg_id uuid;
  v_sess_closed uuid;
  v_sess_open uuid;
  v_sess_id uuid;
  v_sale_id uuid;
  v_first_sale uuid;
  v_id uuid;
  v_count_sales int := 0;
  v_lines int := 0;
  v_prod RECORD;
  r RECORD;
  v_total int;
  v_line_count int;
  v_qty int;
  v_unit int;
  v_line_total int;
BEGIN
  SELECT id INTO v_reg_id FROM pos_registers WHERE active = true LIMIT 1;
  IF v_reg_id IS NULL THEN
    INSERT INTO pos_registers (name, location, currency, default_tax_rate, active)
    VALUES ('Demo Register #1', 'Main store', 'SEK', 25.00, true)
    RETURNING id INTO v_reg_id;
  END IF;

  INSERT INTO pos_sessions (register_id, cashier_name, status, opening_cash_cents, opened_at, closed_at, closing_cash_cents, expected_cash_cents, cash_variance_cents, total_sales_cents, sales_count, notes)
  VALUES (v_reg_id, 'Demo Cashier', 'closed', 100000, now() - interval '8 hours', now() - interval '30 minutes', 250000, 247500, 2500, 0, 0,
          'Closed session — counted cash was 25,00 over expected: this is what a cash variance looks like.')
  RETURNING id INTO v_sess_closed;
  PERFORM _demo_register_row(p_run_id, 'pos_sessions', v_sess_closed);

  INSERT INTO pos_sessions (register_id, cashier_name, status, opening_cash_cents, opened_at, closed_at, closing_cash_cents, expected_cash_cents, cash_variance_cents, total_sales_cents, sales_count, notes)
  VALUES (v_reg_id, 'Demo Cashier', 'open', 100000, now() - interval '2 hours', NULL, NULL, NULL, NULL, 0, 0,
          'Open session — ask your agent to close it and reconcile the drawer.')
  RETURNING id INTO v_sess_open;
  PERFORM _demo_register_row(p_run_id, 'pos_sessions', v_sess_open);

  FOR r IN SELECT * FROM (VALUES
    (false, 'card',  'completed', 300),
    (false, 'swish', 'completed', 240),
    (false, 'card',  'refunded',  180),
    (false, 'cash',  'voided',    120),
    (true,  'cash',  'completed',  10)
  ) AS t(in_open_sess, method, status, mins_ago) LOOP
    v_sess_id := CASE WHEN r.in_open_sess THEN v_sess_open ELSE v_sess_closed END;
    v_total := 0;
    v_line_count := 1 + (v_count_sales % 2);

    INSERT INTO pos_sales (register_id, session_id, cashier_id, subtotal_cents, tax_cents, discount_cents, total_cents, currency, payment_method, status, refund_of, created_at)
    VALUES (v_reg_id, v_sess_id, NULL, 0, 0, 0, 0, 'SEK', r.method, r.status,
            CASE WHEN r.status = 'refunded' THEN v_first_sale ELSE NULL END,
            now() - (r.mins_ago * interval '1 minute'))
    RETURNING id INTO v_sale_id;
    PERFORM _demo_register_row(p_run_id, 'pos_sales', v_sale_id);
    v_count_sales := v_count_sales + 1;
    IF v_first_sale IS NULL THEN
      v_first_sale := v_sale_id;
    END IF;

    FOR v_prod IN SELECT id, name, COALESCE(price_cents, 9900) AS p FROM products WHERE is_active = true ORDER BY created_at LIMIT v_line_count LOOP
      v_qty := 1 + (v_count_sales % 2);
      v_unit := v_prod.p;
      v_line_total := v_qty * v_unit;
      v_total := v_total + v_line_total;
      INSERT INTO pos_sale_lines (sale_id, product_id, product_name, quantity, unit_price_cents, tax_rate, line_total_cents)
      VALUES (v_sale_id, v_prod.id, v_prod.name, v_qty, v_unit, 25.00, v_line_total)
      RETURNING id INTO v_id;
      PERFORM _demo_register_row(p_run_id, 'pos_sale_lines', v_id);
      v_lines := v_lines + 1;
    END LOOP;

    IF v_total = 0 THEN
      v_total := 9900;
      INSERT INTO pos_sale_lines (sale_id, product_name, quantity, unit_price_cents, tax_rate, line_total_cents)
      VALUES (v_sale_id, 'Walk-in item', 1, 9900, 25.00, 9900)
      RETURNING id INTO v_id;
      PERFORM _demo_register_row(p_run_id, 'pos_sale_lines', v_id);
      v_lines := v_lines + 1;
    END IF;

    UPDATE pos_sales SET subtotal_cents = round(v_total/1.25)::int, tax_cents = v_total - round(v_total/1.25)::int, total_cents = v_total WHERE id = v_sale_id;

    IF r.status <> 'voided' THEN
      INSERT INTO pos_payments (sale_id, method, amount_cents)
      VALUES (v_sale_id, r.method, v_total)
      RETURNING id INTO v_id;
      PERFORM _demo_register_row(p_run_id, 'pos_payments', v_id);
    END IF;
  END LOOP;

  UPDATE pos_sessions AS s
     SET total_sales_cents = (SELECT COALESCE(SUM(total_cents),0) FROM pos_sales WHERE session_id = s.id),
        sales_count = (SELECT COUNT(*) FROM pos_sales WHERE session_id = s.id)
   WHERE s.id IN (v_sess_closed, v_sess_open);

  RETURN jsonb_build_object('sales', v_count_sales, 'lines', v_lines);
END $$;


ALTER FUNCTION "public"."seed_demo_pos"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_pricelists"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Standard SEK ('||v_suffix||')',        'Default list — is_default=true, lowest precedence fallback for every customer', 'SEK', true,  100, true,  -30, 365),
    ('Partner 20% ('||v_suffix||')',         'Higher-priority list (lower number wins) — overrides the default for partners', 'SEK', false,  50, true,  -30, 365),
    ('Expired Campaign ('||v_suffix||')',    'Validity window in the past — active flag on, but dates exclude it from pricing', 'SEK', false,  25, true, -120, -30),
    ('Disabled Draft List ('||v_suffix||')', 'Inactive list — is_active=false; ask your agent to finish and activate it',     'SEK', false,  75, false, -30, 365)
  ) AS t(nm,descr,cur,isdef,prio,active,from_off,until_off) LOOP
    INSERT INTO public.pricelists(name,description,currency,is_default,priority,is_active,valid_from,valid_until)
    VALUES (r.nm,r.descr,r.cur,r.isdef,r.prio,r.active,current_date + r.from_off, current_date + r.until_off)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'pricelists',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('pricelists', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_pricelists"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_projects"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_project_id uuid;
  v_task_id uuid;
  v_projects_created int := 0;
  v_tasks_created int := 0;
  v_members_added int := 0;
  v_suffix text := substring(p_run_id::text, 1, 6);
  v_member_ids uuid[];
  v_member_count int;
  prec record;
  trec record;
  v_idx int;
  v_assignee uuid;
BEGIN
  SELECT COALESCE(array_agg(user_id), ARRAY[]::uuid[])
    INTO v_member_ids
  FROM (
    SELECT user_id FROM public.employees
    WHERE user_id IS NOT NULL AND status = 'active'
    ORDER BY created_at ASC
    LIMIT 3
  ) e;
  v_member_count := array_length(v_member_ids, 1);

  FOR prec IN
    SELECT * FROM (VALUES
      ('Demo: Active Project ('||v_suffix||')',   'Acme Retail AB',     'An active project with tasks in every status — todo, in progress, review and done.',                          '#6366f1', 160000, 40, (current_date + 60)::date, true,  true),
      ('Demo: Overdue Project ('||v_suffix||')',  'Sundsvall Tech',     'The deadline has passed — this is what an overdue project looks like. Ask your agent to reschedule or close it.', '#f59e0b', 200000, 30, (current_date - 14)::date, true,  false),
      ('Demo: Archived Project ('||v_suffix||')', 'Malmö Finans Group', 'Archived (is_active = false) — hidden from active views but kept for reporting.',                              '#10b981', 220000, 20, (current_date - 90)::date, false, false)
    ) AS t(p_name, p_client, p_desc, p_color, p_rate, p_budget, p_deadline, p_active, p_seed_tasks)
  LOOP
    INSERT INTO public.projects (name, client_name, description, color, hourly_rate_cents, currency, is_billable, is_active, budget_hours, deadline)
    VALUES (prec.p_name, prec.p_client, prec.p_desc, prec.p_color, prec.p_rate, 'SEK', true, prec.p_active, prec.p_budget, prec.p_deadline)
    RETURNING id INTO v_project_id;

    PERFORM public._demo_register_row(p_run_id, 'projects', v_project_id);
    v_projects_created := v_projects_created + 1;

    IF v_member_count IS NOT NULL AND v_member_count > 0 THEN
      FOR v_idx IN 1..v_member_count LOOP
        INSERT INTO public.project_members (project_id, user_id, role, tracks_time)
        VALUES (v_project_id, v_member_ids[v_idx],
                CASE WHEN v_idx = 1 THEN 'lead' ELSE 'member' END, true)
        ON CONFLICT (project_id, user_id) DO NOTHING;
        v_members_added := v_members_added + 1;
      END LOOP;
    END IF;

    IF prec.p_seed_tasks THEN
      v_idx := 0;
      FOR trec IN
        SELECT * FROM (VALUES
          ('Kickoff workshop — done',                          'done',         'medium', 0),
          ('Backend integration — in progress',                'in_progress',  'high',   1),
          ('Design system — waiting in review',                'review',       'urgent', 2),
          ('Launch checklist — todo. Ask your agent to plan it','todo',        'low',    3)
        ) AS t(p_title, p_status, p_priority, p_sort)
      LOOP
        v_assignee := NULL;
        IF v_member_count IS NOT NULL AND v_member_count > 0 THEN
          v_assignee := v_member_ids[(v_idx % v_member_count) + 1];
        END IF;

        INSERT INTO public.project_tasks (project_id, title, status, priority, sort_order, completed_at, estimated_hours, assigned_to)
        VALUES (
          v_project_id,
          trec.p_title,
          trec.p_status::project_task_status,
          trec.p_priority::project_task_priority,
          trec.p_sort,
          CASE WHEN trec.p_status = 'done' THEN now() - ((5 - trec.p_sort) || ' days')::interval ELSE NULL END,
          4 + trec.p_sort,
          v_assignee
        )
        RETURNING id INTO v_task_id;

        PERFORM public._demo_register_row(p_run_id, 'project_tasks', v_task_id);
        v_tasks_created := v_tasks_created + 1;
        v_idx := v_idx + 1;
      END LOOP;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'projects_created', v_projects_created,
    'tasks_created', v_tasks_created,
    'members_added', v_members_added,
    'team_size', COALESCE(v_member_count, 0)
  );
END $$;


ALTER FUNCTION "public"."seed_demo_projects"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";