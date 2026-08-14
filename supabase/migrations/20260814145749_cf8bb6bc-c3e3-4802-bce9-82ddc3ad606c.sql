CREATE OR REPLACE FUNCTION "public"."seed_demo_ecommerce"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count int := 0;
  v_products_created int := 0;
  v_order_id uuid;
  v_item_id uuid;
  v_prod_id uuid;
  v_product_ids uuid[];
  v_product_names text[];
  v_product_prices int[];
  rec record;
  prec record;
  v_idx int;
  v_pick_id uuid;
  v_pick_name text;
  v_pick_price int;
  v_total int;
BEGIN
  FOR prec IN
    SELECT * FROM (VALUES
      ('Demo: Starter Plan',      'A one-time product (type = one_time) — shown in the shop.',                                              'one_time',  49900, true,  'demo-starter-plan'),
      ('Demo: Pro Subscription',  'A recurring product (type = recurring) — pairs with the subscriptions module.',                          'recurring', 99900, true,  'demo-pro-subscription'),
      ('Demo: Onboarding Pack',   'A one-time service product with a higher price point.',                                                  'one_time',  79900, true,  'demo-onboarding-pack'),
      ('Demo: Legacy Add-on',     'Inactive product (is_active = false) — hidden from the shop. Ask your agent to relaunch or retire it.',  'one_time',  29900, false, 'demo-legacy-addon')
    ) AS t(p_name, p_desc, p_type, p_price, p_active, p_seed)
  LOOP
    INSERT INTO public.products (name, description, type, price_cents, currency, is_active, sort_order, image_url)
    VALUES (
      prec.p_name, prec.p_desc, prec.p_type::product_type, prec.p_price, 'SEK', prec.p_active, v_products_created,
      'https://picsum.photos/seed/' || prec.p_seed || '/800/600'
    )
    RETURNING id INTO v_prod_id;

    PERFORM public._demo_register_row(p_run_id, 'products', v_prod_id);
    v_products_created := v_products_created + 1;
  END LOOP;

  SELECT array_agg(id), array_agg(name), array_agg(price_cents)
    INTO v_product_ids, v_product_names, v_product_prices
  FROM (
    SELECT id, name, price_cents
    FROM public.products
    WHERE is_active = true AND price_cents > 0
    ORDER BY sort_order NULLS LAST, created_at
    LIMIT 12
  ) p;

  IF v_product_ids IS NULL OR array_length(v_product_ids, 1) = 0 THEN
    RETURN jsonb_build_object('products_created', v_products_created, 'orders_created', 0, 'skipped', 'no active products');
  END IF;

  FOR rec IN
    SELECT * FROM (VALUES
      ('Anna Lindberg',    'anna.lindberg@example.demo', 'pending',   'unfulfilled', 0, 'Awaiting payment — nothing to fulfil yet.'),
      ('Erik Johansson',   'erik.j@example.demo',        'paid',      'unfulfilled', 1, 'Paid but unfulfilled — ask your agent to pick, pack and ship it.'),
      ('Sofia Bergström',  'sofia.b@example.demo',       'paid',      'packed',      2, 'Packed and ready for carrier pickup.'),
      ('Lars Nilsson',     'lars.nilsson@example.demo',  'paid',      'shipped',     4, 'Shipped — tracking number attached.'),
      ('Maria Andersson',  'maria.a@example.demo',       'completed', 'delivered',   7, 'Delivered and completed — the end state.'),
      ('Nils Olsson',      'nils.o@example.demo',        'refunded',  'unfulfilled', 9, 'Refunded before fulfilment — no shipping timestamps.')
    ) AS t(customer, email, status, fulfillment, days_ago, note)
  LOOP
    v_idx := (v_count % array_length(v_product_ids, 1)) + 1;
    v_pick_id := v_product_ids[v_idx];
    v_pick_name := v_product_names[v_idx];
    v_pick_price := v_product_prices[v_idx];
    v_total := v_pick_price * (1 + (v_count % 2));

    INSERT INTO public.orders (
      customer_email, customer_name, status, fulfillment_status,
      total_cents, currency, metadata, created_at,
      picked_at, packed_at, shipped_at, delivered_at,
      tracking_number, tracking_url, fulfillment_notes
    ) VALUES (
      rec.email, rec.customer, rec.status, rec.fulfillment,
      v_total, 'SEK', jsonb_build_object('demo', true), now() - (rec.days_ago || ' days')::interval,
      CASE WHEN rec.fulfillment IN ('picked','packed','shipped','delivered') THEN now() - ((rec.days_ago - 0) || ' days')::interval ELSE NULL END,
      CASE WHEN rec.fulfillment IN ('packed','shipped','delivered') THEN now() - ((rec.days_ago - 0) || ' days')::interval ELSE NULL END,
      CASE WHEN rec.fulfillment IN ('shipped','delivered') THEN now() - ((rec.days_ago - 1) || ' days')::interval ELSE NULL END,
      CASE WHEN rec.fulfillment = 'delivered' THEN now() - ((rec.days_ago - 2) || ' days')::interval ELSE NULL END,
      CASE WHEN rec.fulfillment IN ('shipped','delivered') THEN 'DEMO' || lpad((v_count + 1)::text, 6, '0') ELSE NULL END,
      CASE WHEN rec.fulfillment IN ('shipped','delivered') THEN 'https://tracking.example.demo/DEMO' || lpad((v_count + 1)::text, 6, '0') ELSE NULL END,
      rec.note
    )
    RETURNING id INTO v_order_id;

    PERFORM public._demo_register_row(p_run_id, 'orders', v_order_id);

    INSERT INTO public.order_items (order_id, product_id, product_name, quantity, price_cents)
    VALUES (v_order_id, v_pick_id, v_pick_name, 1 + (v_count % 2), v_pick_price)
    RETURNING id INTO v_item_id;

    PERFORM public._demo_register_row(p_run_id, 'order_items', v_item_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('products_created', v_products_created, 'orders_created', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_ecommerce"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_expenses"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_user uuid; rec record;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    SELECT user_id INTO v_user FROM public.user_roles WHERE role='admin'::app_role LIMIT 1;
  END IF;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('table','expenses','inserted',0,'skipped','no admin user');
  END IF;
  FOR rec IN SELECT * FROM (VALUES
    ('Draft expense — taxi receipt. Ask your agent to submit it.',        'travel',    45000,  9000,  'Demo Taxi',           'draft'),
    ('Submitted expense — awaiting approval decision',                    'office',    12000,  2400,  'Demo Office Supply',  'submitted'),
    ('Approved expense — ready to be booked to the ledger',               'training',  250000, 50000, 'TechConf Demo',       'approved'),
    ('Rejected expense — missing receipt; can be edited and resubmitted', 'travel',    62000,  12400, 'Demo Restaurant',     'rejected'),
    ('Booked expense — posted to accounting as a journal entry',          'office',    8900,   1780,  'Demo Software',       'booked'),
    ('Paid expense — reimbursed to the employee; end of the lifecycle',   'travel',    31000,  6200,  'Demo Hotel',          'paid')
  ) AS t(description, category, amount, vat, vendor, status_) LOOP
    INSERT INTO public.expenses (user_id, expense_date, description, amount_cents, vat_cents, currency, category, vendor, status)
    VALUES (v_user, CURRENT_DATE - (v_count*3), rec.description, rec.amount, rec.vat, 'SEK', rec.category, rec.vendor||' [demo:'||p_scenario||']', rec.status_)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'expenses',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('table','expenses','inserted',v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_expenses"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_hr"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('Anna Lindberg',  'anna.lindberg+'||substring(p_run_id::text,1,6)||'@demo.flowwink.com',  'CTO',                'Engineering', 'full_time',  75000, 'active',     NULL::int, 'Active full-time employee — the default state.'),
    ('Sara Johansson', 'sara.j+'||substring(p_run_id::text,1,6)||'@demo.flowwink.com',         'Head of Sales',      'Sales',       'full_time',  60000, 'active',     NULL,      'Active — appears in org chart, headcount and payroll.'),
    ('Johan Persson',  'johan.p+'||substring(p_run_id::text,1,6)||'@demo.flowwink.com',        'Support Specialist', 'Support',     'part_time',  30000, 'active',     NULL,      'Part-time (employment_type = part_time).'),
    ('Linda Karlsson', 'linda.k+'||substring(p_run_id::text,1,6)||'@demo.flowwink.com',        'Marketing Lead',     'Marketing',   'full_time',  50000, 'on_leave',   NULL,      'On parental leave (status = on_leave) — still employed, excluded from active views.'),
    ('Erik Nilsson',   'erik.n+'||substring(p_run_id::text,1,6)||'@demo.flowwink.com',         'Contract Developer', 'Engineering', 'contractor', 45000, 'terminated', 30,        'Terminated contractor with an end date — kept for history. Ask your agent to run offboarding next time.')
  ) AS t(name,email,title,dept,etype,salary,status,end_days_ago,note) LOOP
    INSERT INTO public.employees(name,email,title,department,employment_type,start_date,monthly_salary_cents,status,end_date,notes)
    VALUES (r.name,r.email,r.title,r.dept,r.etype,current_date - (200 + v_count*150), r.salary*100, r.status,
            CASE WHEN r.end_days_ago IS NOT NULL THEN current_date - r.end_days_ago ELSE NULL END,
            r.note)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'employees',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('employees', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_hr"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_inventory"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_main_loc uuid;
  v_vendor_loc uuid;
  v_cust_loc uuid;
  v_product RECORD;
  v_first_prod uuid;
  v_quant_id uuid;
  v_move_id uuid;
  v_quants int := 0;
  v_moves int := 0;
  v_qty int;
BEGIN
  SELECT id INTO v_main_loc FROM stock_locations WHERE code='WH/MAIN' LIMIT 1;
  SELECT id INTO v_vendor_loc FROM stock_locations WHERE code='WH/VENDORS' LIMIT 1;
  SELECT id INTO v_cust_loc FROM stock_locations WHERE code='WH/CUSTOMERS' LIMIT 1;

  IF v_main_loc IS NULL THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'no main warehouse');
  END IF;

  FOR v_product IN
    SELECT id, name FROM products WHERE is_active = true ORDER BY created_at LIMIT 3
  LOOP
    v_qty := 40 + v_quants * 20;

    INSERT INTO stock_quants (product_id, location_id, quantity, reserved_quantity)
    VALUES (v_product.id, v_main_loc, v_qty, 0)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_quant_id;

    IF v_quant_id IS NOT NULL THEN
      INSERT INTO demo_run_items (run_id, table_name, row_id) VALUES (p_run_id, 'stock_quants', v_quant_id);
      v_quants := v_quants + 1;
    END IF;

    INSERT INTO stock_moves (product_id, quantity, move_type, from_location_id, to_location_id, state, notes, reference_type)
    VALUES (v_product.id, v_qty, 'in', v_vendor_loc, v_main_loc, 'done', 'Completed receipt (move_type = in, state = done) — this filled the on-hand quant.', 'demo-seed')
    RETURNING id INTO v_move_id;
    INSERT INTO demo_run_items (run_id, table_name, row_id) VALUES (p_run_id, 'stock_moves', v_move_id);
    v_moves := v_moves + 1;

    IF v_first_prod IS NULL THEN
      v_first_prod := v_product.id;
    END IF;
  END LOOP;

  IF v_first_prod IS NOT NULL THEN
    INSERT INTO stock_moves (product_id, quantity, move_type, from_location_id, to_location_id, state, notes, reference_type)
    VALUES (v_first_prod, 15, 'in', v_vendor_loc, v_main_loc, 'draft', 'Draft receipt (state = draft) — not counted in stock yet. Ask your agent to confirm it.', 'demo-seed')
    RETURNING id INTO v_move_id;
    INSERT INTO demo_run_items (run_id, table_name, row_id) VALUES (p_run_id, 'stock_moves', v_move_id);
    v_moves := v_moves + 1;

    INSERT INTO stock_moves (product_id, quantity, move_type, from_location_id, to_location_id, state, notes, reference_type)
    VALUES (v_first_prod, 5, 'out', v_main_loc, v_cust_loc, 'done', 'Customer shipment (move_type = out, state = done).', 'demo-seed')
    RETURNING id INTO v_move_id;
    INSERT INTO demo_run_items (run_id, table_name, row_id) VALUES (p_run_id, 'stock_moves', v_move_id);
    v_moves := v_moves + 1;

    INSERT INTO stock_moves (product_id, quantity, move_type, from_location_id, to_location_id, state, notes, reference_type)
    VALUES (v_first_prod, 10, 'out', v_main_loc, v_cust_loc, 'cancelled', 'Cancelled shipment (state = cancelled) — never affected stock.', 'demo-seed')
    RETURNING id INTO v_move_id;
    INSERT INTO demo_run_items (run_id, table_name, row_id) VALUES (p_run_id, 'stock_moves', v_move_id);
    v_moves := v_moves + 1;
  END IF;

  RETURN jsonb_build_object('quants', v_quants, 'moves', v_moves);
END;
$$;


ALTER FUNCTION "public"."seed_demo_inventory"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_invoices"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_number text; rec record;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('Draft Invoice Demo AB',   'kontakt@draft.demo',    'draft',     18000, -2,  25, 'Draft state — not yet sent. Ask your agent to review and send it.'),
    ('Sent Invoice Demo AB',    'info@sent.demo',        'sent',      45000, -10, 20, 'Sent state — awaiting payment, due date in the future.'),
    ('Paid Invoice Demo AB',    'ekonomi@paid.demo',     'paid',      92000, -30, -5, 'Paid state — settled in full; paid_at and paid_amount_cents are set.'),
    ('Overdue Invoice Demo AB', 'faktura@overdue.demo',  'overdue',   36000, -40, -12,'Overdue state — due date passed, unpaid. This is the row the dunning automation acts on.'),
    ('Cancelled Invoice Demo',  'admin@cancelled.demo',  'cancelled', 12000, -20, 10, 'Cancelled state — voided before payment; excluded from receivables.')
  ) AS t(customer, email, status, total, issue_offset, due_offset, note) LOOP
    v_number := 'DEMO-INV-'||substring(p_run_id::text,1,6)||'-'||lpad((v_count+1)::text,3,'0');
    INSERT INTO public.invoices (invoice_number, status, customer_name, customer_email, subtotal_cents, tax_cents, total_cents, currency, issue_date, due_date, line_items, notes, paid_at, paid_amount_cents)
    VALUES (v_number, rec.status::invoice_status, rec.customer, rec.email,
      (rec.total*0.8)::int, (rec.total*0.2)::int, rec.total, 'SEK',
      CURRENT_DATE+rec.issue_offset, CURRENT_DATE+rec.due_offset,
      jsonb_build_array(jsonb_build_object('description','Demo services','quantity',1,'unit_price_cents',(rec.total*0.8)::int)),
      'demo:'||p_scenario||' — '||rec.note,
      CASE WHEN rec.status='paid' THEN now() ELSE NULL END,
      CASE WHEN rec.status='paid' THEN rec.total ELSE 0 END)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'invoices',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('table','invoices','inserted',v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_invoices"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";