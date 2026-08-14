CREATE OR REPLACE FUNCTION "public"."seed_demo_consultants"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; rec record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR rec IN SELECT * FROM (VALUES
    ('Anna Lindberg',   'Senior Frontend Engineer', 'Available — free to start a new assignment now. Ask your agent to match her against an open request.',                              ARRAY['React','TypeScript','Tailwind','Design Systems'], 8,  1450, 'available',           ARRAY['Swedish','English'], true),
    ('Erik Johansson',  'Cloud Architect',          'Partially available — booked around 50%, can take a part-time engagement alongside the current one.',                               ARRAY['AWS','Terraform','Kubernetes','Node.js'],         12, 1850, 'partially_available', ARRAY['Swedish','English'], true),
    ('Sofia Bergström', 'Product Designer',         'Unavailable — fully booked on a client assignment. Keep on the bench list and revisit when it ends.',                               ARRAY['Figma','Prototyping','User Research'],            10, 1350, 'unavailable',         ARRAY['Swedish','English'], true),
    ('Lars Nilsson',    'Backend Engineer',         'Inactive profile — hidden from listings and matching. Ask your agent to review, update the skills and reactivate it.',              ARRAY['Go','PostgreSQL','gRPC'],                          9,  1500, 'available',           ARRAY['Swedish','English'], false)
  ) AS t(full_name, role_title, summary_text, skill_arr, exp_years, rate_per_hour, avail_status, lang_arr, active_flag) LOOP
    INSERT INTO public.consultant_profiles (name, title, email, summary, bio, skills, experience_years, hourly_rate_cents, currency, availability, languages, is_active)
    VALUES (rec.full_name, rec.role_title,
      lower(replace(rec.full_name,' ','.'))||'+'||v_suffix||'@example.demo',
      rec.summary_text, rec.summary_text, rec.skill_arr, rec.exp_years,
      rec.rate_per_hour*100, 'SEK', rec.avail_status, rec.lang_arr, rec.active_flag)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'consultant_profiles',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('table','consultant_profiles','inserted',v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_consultants"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_contracts"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; v_body text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Draft: SOW – Northwind ('||v_suffix||')',              'service'::contract_type, 'draft'::contract_status,             'Northwind Trading',   'procurement+'||v_suffix||'@northwind.example', NULL::date,                 NULL::date,                 'none'::renewal_type,  4500000::bigint, 'SEK', NULL::timestamptz,           NULL::timestamptz,          'Status draft: not yet sent — ask your agent to finish the body and send it for signature.'),
    ('Pending signature: Reseller – Gamma EU ('||v_suffix||')','other'::contract_type, 'pending_signature'::contract_status, 'Gamma EU GmbH',       'contracts+'||v_suffix||'@gamma.example',       (current_date - 5)::date,   (current_date + 360)::date, 'auto'::renewal_type, 25000000::bigint, 'EUR', NULL,                         NULL,                        'Status pending_signature: sent and awaiting the counterparty''s signature.'),
    ('Active: MSA – Acme Corp ('||v_suffix||')',             'service'::contract_type, 'active'::contract_status,            'Acme Corp AB',        'legal+'||v_suffix||'@acme.example',            (current_date - 335)::date, (current_date + 30)::date,  'auto'::renewal_type, 12000000::bigint, 'SEK', now() - interval '335 days',  NULL,                        'Status active with auto-renewal and end_date ~30 days out — this is what the renewal radar watches.'),
    ('Expired: NDA – Beta Industries ('||v_suffix||')',      'nda'::contract_type,     'expired'::contract_status,           'Beta Industries Ltd', 'legal+'||v_suffix||'@beta.example',            (current_date - 800)::date, (current_date - 60)::date,  'none'::renewal_type,        0::bigint, 'SEK', now() - interval '800 days',  NULL,                        'Status expired: end_date has passed with no renewal.'),
    ('Terminated: Lease – Delta Co ('||v_suffix||')',        'lease'::contract_type,   'terminated'::contract_status,        'Delta Co',            'admin+'||v_suffix||'@delta.example',           (current_date - 400)::date, (current_date + 330)::date, 'manual'::renewal_type, 8000000::bigint, 'SEK', now() - interval '400 days',  now() - interval '30 days',  'Status terminated: ended before end_date — terminated_at records when.')
  ) AS t(title,ctype,cstatus,cname,cmail,sd,ed,rt,val,cur,signed,term,note) LOOP
    v_body := E'# ' || r.title || E'\n\n'
      || E'**Parties.** This agreement is entered into between the Provider and ' || r.cname || E'.\n\n'
      || E'## 1. Scope\nThe Provider shall deliver the agreed services described in the accompanying Statement of Work. This demo contract is generated automatically as part of demo data.\n\n'
      || E'## 2. Term\nThe agreement starts on the effective date and remains in force until terminated by either party with written notice in accordance with the renewal terms.\n\n'
      || E'## 3. Fees\nFees and currency are as stated in the contract metadata. Invoices are issued monthly in arrears unless otherwise agreed.\n\n'
      || E'## 4. Confidentiality\nBoth parties shall keep all non-public information confidential and shall not disclose it to any third party without prior written consent.\n\n'
      || E'## 5. Governing law\nThis agreement is governed by Swedish law. Disputes shall be resolved by the courts of Stockholm.\n\n'
      || E'_Seeded by demo run ' || v_suffix || E'._';
    INSERT INTO public.contracts(title,contract_type,status,counterparty_name,counterparty_email,start_date,end_date,renewal_type,value_cents,currency,notes,body_markdown,signed_at,terminated_at)
    VALUES (r.title,r.ctype,r.cstatus,r.cname,r.cmail,r.sd,r.ed,r.rt,r.val,r.cur,r.note,v_body,r.signed,r.term) RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'contracts',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('contracts', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_contracts"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_crm"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_lead_id uuid; rec record;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('New lead: Anna Lindberg',    'anna.lindberg+'||substring(p_run_id::text,1,6)||'@nordicfin.demo',  'lead',        35, false, 'Status lead: fresh inbound, unqualified. Ask your agent to qualify and score this lead.',            NULL::timestamptz, NULL::text),
    ('Flagged: Maria Holm',        'maria+'||substring(p_run_id::text,1,6)||'@holm-consulting.demo',    'lead',        55, true,  'Status lead with needs_review = true: the AI wants a human look before qualifying further.',          NULL, NULL),
    ('Opportunity: Johan Persson', 'johan+'||substring(p_run_id::text,1,6)||'@persson-tech.demo',       'opportunity', 88, false, 'Status opportunity: qualified and deal-ready. Ask your agent to create a deal from this lead.',       NULL, NULL),
    ('Customer: Erik Sjöberg',     'erik+'||substring(p_run_id::text,1,6)||'@sjoberg-bygg.demo',        'customer',    95, false, 'Status customer: converted_at marks when this lead became a customer.',                               now() - interval '30 days', NULL),
    ('Lost: Sara Eklund',          'sara.eklund+'||substring(p_run_id::text,1,6)||'@eklundlaw.demo',    'lost',        40, false, 'Status lost: lost_reason records WHY — lost-discipline keeps the pipeline honest.',                   NULL, 'No budget this year')
  ) AS t(name, email, status, score, review, summary, conv, lostr) LOOP
    INSERT INTO public.leads (email, name, status, score, source, ai_summary, needs_review, converted_at, lost_reason)
    VALUES (rec.email, rec.name, rec.status::lead_status, rec.score, 'demo:'||p_scenario, rec.summary, rec.review, rec.conv, rec.lostr)
    RETURNING id INTO v_lead_id;
    PERFORM public._demo_register_row(p_run_id, 'leads', v_lead_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('table','leads','inserted',v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_crm"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_deals"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_lead uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Anders Lind',    'anders+'||v_suffix||'@helios.example',   'Stage prospecting: first contact made — ask your agent for a research brief on this company', 'prospecting'::deal_stage,  1200000, (current_date + 60)::date, NULL::text),
    ('Marcus Berg',    'marcus+'||v_suffix||'@northwind.example','Stage qualified: budget and need confirmed, ready for a proposal',                            'qualified'::deal_stage,    4500000, (current_date + 45)::date, NULL),
    ('Lisa Andersson', 'lisa+'||v_suffix||'@acme.example',       'Stage proposal: quote is out — ask your agent to draft the follow-up',                        'proposal'::deal_stage,    18000000, (current_date + 30)::date, NULL),
    ('Sara Holm',      'sara+'||v_suffix||'@gamma.example',      'Stage negotiation: terms under discussion, expected close is near',                           'negotiation'::deal_stage, 25000000, (current_date + 14)::date, NULL),
    ('Eva Norén',      'eva+'||v_suffix||'@lumen.example',       'Stage closed_won: closed_at is set the moment a deal closes',                                 'closed_won'::deal_stage,   9800000, (current_date - 7)::date,  NULL),
    ('Karin Ek',       'karin+'||v_suffix||'@vertex.example',    'Stage closed_lost: lost_reason records WHY — lost-discipline keeps the pipeline honest',      'closed_lost'::deal_stage,  6000000, (current_date - 3)::date,  'Chose competitor on price')
  ) AS t(nm,em,title,stg,val,close,lostr) LOOP
    INSERT INTO public.leads(name,email,status,source,ai_summary)
    VALUES (r.nm,r.em,'opportunity'::lead_status,'demo','Lead for deal: '||r.title) RETURNING id INTO v_lead;
    PERFORM public._demo_register_row(p_run_id,'leads',v_lead);
    INSERT INTO public.deals(lead_id,stage,value_cents,currency,expected_close,notes,closed_at,lost_reason)
    VALUES (v_lead,r.stg,r.val,'SEK',r.close,r.title, CASE WHEN r.stg IN ('closed_won','closed_lost') THEN now() - interval '7 days' ELSE NULL END, r.lostr)
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'deals',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('deals', v_count, 'leads', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_deals"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."seed_demo_documents"("p_run_id" "uuid", "p_scenario" "text" DEFAULT 'default'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_count int := 0; v_id uuid; v_suffix text; r record;
BEGIN
  v_suffix := substring(p_run_id::text,1,6);
  FOR r IN SELECT * FROM (VALUES
    ('Extracted and searchable — the agent can read this one ('||v_suffix||')', 'employee-handbook.md', 'text/markdown', 'hr', 'Policies',
      'Extraction succeeded: the markdown body below is indexed, so search and your agent can quote it.',
      E'# Employee Handbook\n\n## Working hours\nStandard week is 40h. Flexible start between 07:00 and 10:00.\n\n## Leave\n25 paid vacation days per year.\n\n## Expenses\nSubmit within 30 days via the Expenses module. Receipts required.\n\nThis document shows extraction_status = success: its text is searchable and readable by the agent.',
      'success', NULL),
    ('Waiting for extraction — content not readable yet ('||v_suffix||')', 'quarterly-report.pdf', 'application/pdf', 'finance', 'Reports',
      'Extraction is pending: the file is stored but its text has not been indexed, so the agent cannot read it yet.',
      NULL, 'pending', NULL),
    ('Extraction failed — password-protected PDF ('||v_suffix||')', 'signed-agreement-locked.pdf', 'application/pdf', 'legal', 'Contracts',
      'Extraction failed and the error is recorded. Re-upload without password protection, or ask your agent to chase the sender for an unlocked copy.',
      NULL, 'failed', 'Encrypted PDF: the text layer could not be read.'),
    ('Unsupported format — stored but never indexed ('||v_suffix||')', 'design-assets.zip', 'application/zip', 'marketing', 'Brand',
      'Archives are kept as files only: extraction_status = unsupported means no text extraction is attempted for this type.',
      NULL, 'unsupported', NULL),
    ('Image file — extraction not applicable ('||v_suffix||')', 'logo-primary.png', 'image/png', 'marketing', 'Brand',
      'Images get extraction_status = not_applicable: nothing to extract, and that is expected rather than an error.',
      NULL, 'not_applicable', NULL)
  ) AS t(title,fname,ftype,cat,folder,descr,md,xstatus,xerr) LOOP
    INSERT INTO public.documents(title,file_name,file_url,file_type,category,folder,description,content_md,extraction_status,extraction_error,content_extracted_at,source,tags)
    VALUES (r.title, r.fname, 'demo://'||r.fname, r.ftype, r.cat, r.folder, r.descr, r.md, r.xstatus, r.xerr,
            CASE WHEN r.xstatus='success' THEN now() ELSE NULL END, 'demo-seed', ARRAY['demo', r.cat])
    RETURNING id INTO v_id;
    PERFORM public._demo_register_row(p_run_id,'documents',v_id);
    v_count := v_count+1;
  END LOOP;
  RETURN jsonb_build_object('documents', v_count);
END $$;


ALTER FUNCTION "public"."seed_demo_documents"("p_run_id" "uuid", "p_scenario" "text") OWNER TO "postgres";