-- Rollsvepet #102, P1: hela moduler som fasader. Tabellerna nedan gav rollen
-- nav + sida men nekade varje skrivning, eftersom policyn krävde admin — eller
-- rollen `employee`, som finns i enumet men inte i ROLE_LABELS och därför
-- aldrig kan tilldelas (grinden var i praktiken admin-only, tyst).
--
-- Mönstret är ADDITIVT (samma som 20260817220000): matrispolicyn läggs BREDVID
-- befintliga policies (permissive OR), så admin-, self-, manager- och
-- approver-vägarna överlever orörda. is_manager_of är en ORGANISATORISK
-- radnivårelation och samexisterar medvetet med modulgrinden (ordförandebeslut
-- 2026-08-17): matrisen svarar på "får rollen röra modulen", chefsrelationen
-- på "får personen röra just denna rad".

-- ── 1. Enkla "modulen förvaltar tabellen"-policies ──────────────────────────
DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      -- HR-paritetstabellerna → hr
      ('salary_grades',         'hr',         'ALL'),
      ('benefit_plans',         'hr',         'ALL'),
      ('employee_benefits',     'hr',         'ALL'),
      ('training_courses',      'hr',         'ALL'),
      ('training_enrollments',  'hr',         'ALL'),
      ('disciplinary_actions',  'hr',         'ALL'),
      ('shifts',                'hr',         'ALL'),
      ('leave_requests',        'hr',         'ALL'),
      -- Bokföringen → accounting
      ('journal_entries',        'accounting', 'ALL'),
      ('journal_entry_documents','accounting', 'ALL'),
      -- Plock → inventory (ersätter den döda employee-läsvägen additivt)
      ('picking_orders',        'inventory',  'ALL'),
      ('picking_lines',         'inventory',  'ALL'),
      -- Tidsattestering → timesheets (self-vägarna kvarstår)
      ('time_entries',          'timesheets', 'ALL')
    ) AS v(tbl, module_id, cmd)
  LOOP
    IF to_regclass('public.' || t.tbl) IS NULL THEN
      RAISE NOTICE 'Table % missing here — skipping', t.tbl;
      CONTINUE;
    END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   t.module_id || ' module manages ' || t.tbl, t.tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL
         USING (public.can_access_module(auth.uid(), %L))
         WITH CHECK (public.can_access_module(auth.uid(), %L))',
      t.module_id || ' module manages ' || t.tbl, t.tbl, t.module_id, t.module_id);
  END LOOP;
END $$;

-- ── 1b. journal_entries läsning: "Authenticated users can read" (USING true)
--        lät även KUNDER läsa huvudboken via PostgREST. Läsning stramas till
--        personal (is_staff) — varje inloggad medarbetares dashboards överlever,
--        kundportalen har inget där att göra. Fynd under #102-svepet.
DO $$
BEGIN
  IF to_regclass('public.journal_entries') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Authenticated users can read journal entries" ON public.journal_entries;
    DROP POLICY IF EXISTS "staff read journal_entries" ON public.journal_entries;
    CREATE POLICY "staff read journal_entries" ON public.journal_entries
      FOR SELECT USING (public.is_staff(auth.uid()));
  END IF;
END $$;

-- ── 2. canned_responses: två konsumentytor (tickets + liveSupport) ──────────
DO $$
BEGIN
  IF to_regclass('public.canned_responses') IS NOT NULL THEN
    DROP POLICY IF EXISTS "support modules manage canned_responses" ON public.canned_responses;
    CREATE POLICY "support modules manage canned_responses" ON public.canned_responses
      FOR ALL
      USING (public.can_access_module(auth.uid(), 'tickets')
             OR public.can_access_module(auth.uid(), 'liveSupport'))
      WITH CHECK (public.can_access_module(auth.uid(), 'tickets')
                  OR public.can_access_module(auth.uid(), 'liveSupport'));
  END IF;
END $$;

-- ── 3. expense_reports: attestknapparna var UI-grindade på isAdmin, men även
--       RLS tillät bara admin att uppdatera andras rapporter. Modulbeviljad
--       personal (accounting-rollen) får nu läsa + attestera. INSERT/DELETE
--       förblir ägare/admin — man skapar inte utlägg åt andra.
DO $$
BEGIN
  IF to_regclass('public.expense_reports') IS NOT NULL THEN
    DROP POLICY IF EXISTS "expenses module reviews expense_reports" ON public.expense_reports;
    CREATE POLICY "expenses module reviews expense_reports" ON public.expense_reports
      FOR SELECT USING (public.can_access_module(auth.uid(), 'expenses'));
    DROP POLICY IF EXISTS "expenses module approves expense_reports" ON public.expense_reports;
    CREATE POLICY "expenses module approves expense_reports" ON public.expense_reports
      FOR UPDATE USING (public.can_access_module(auth.uid(), 'expenses'))
      WITH CHECK (public.can_access_module(auth.uid(), 'expenses'));
  END IF;
END $$;

-- ── 4. manage_canned_response: grinden byter döda employee-rollen mot
--       matrisen. Kroppen är live-versionen (optic 2026-08-17) med ENBART
--       v_writer/v_reader ändrade — repo blir källa framåt.
CREATE OR REPLACE FUNCTION public.manage_canned_response(p_action text, p_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_shortcut text DEFAULT NULL::text, p_body_md text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_is_active boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_writer boolean := (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin')
                       OR can_access_module(auth.uid(), 'tickets')
                       OR can_access_module(auth.uid(), 'liveSupport'));
  v_reader boolean := (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin')
                       OR can_access_module(auth.uid(), 'tickets')
                       OR can_access_module(auth.uid(), 'liveSupport'));
  v_id uuid; v_result jsonb;
BEGIN
  IF p_action IN ('create','update','delete') AND NOT v_writer THEN
    RAISE EXCEPTION 'Only roles granted the tickets or liveSupport module can modify canned responses';
  END IF;
  IF p_action IN ('list','get') AND NOT v_reader THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;
  IF p_action = 'list' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.title), '[]'::jsonb) INTO v_result
    FROM (SELECT * FROM canned_responses WHERE p_is_active IS NULL OR is_active = p_is_active
          ORDER BY title LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),200)) c;
    RETURN jsonb_build_object('success', true, 'canned_responses', v_result);
  ELSIF p_action = 'get' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION 'p_id is required'; END IF;
    SELECT to_jsonb(c) INTO v_result FROM canned_responses c WHERE id = p_id;
    IF v_result IS NULL THEN RAISE EXCEPTION 'Canned response % not found', p_id; END IF;
    RETURN jsonb_build_object('success', true, 'canned_response', v_result);
  ELSIF p_action = 'create' THEN
    IF p_title IS NULL OR p_body_md IS NULL THEN RAISE EXCEPTION 'p_title and p_body_md are required'; END IF;
    INSERT INTO canned_responses (title, shortcut, body_md, category, is_active, created_by)
    VALUES (p_title, p_shortcut, p_body_md, p_category, COALESCE(p_is_active, true), auth.uid())
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('success', true, 'id', v_id);
  ELSIF p_action = 'update' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION 'p_id is required'; END IF;
    UPDATE canned_responses SET
      title = COALESCE(p_title, title),
      shortcut = COALESCE(p_shortcut, shortcut),
      body_md = COALESCE(p_body_md, body_md),
      category = COALESCE(p_category, category),
      is_active = COALESCE(p_is_active, is_active)
    WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Canned response % not found', p_id; END IF;
    RETURN jsonb_build_object('success', true, 'id', p_id);
  ELSIF p_action = 'delete' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION 'p_id is required'; END IF;
    DELETE FROM canned_responses WHERE id = p_id;
    RETURN jsonb_build_object('success', true, 'deleted', p_id);
  ELSE
    RAISE EXCEPTION 'Unknown action: %. Use list|get|create|update|delete', p_action;
  END IF;
END; $function$;

-- ── 5. manage_journal_entry_document: 14/8-migrationen återinförde
--       admin/approver-mönstret EFTER matrisflytten. Grinden får matrisledet;
--       admin- och approver-vägarna kvarstår. Kroppen är live-versionen med
--       ENBART grindvillkoret ändrat.
CREATE OR REPLACE FUNCTION public.manage_journal_entry_document(p_action text DEFAULT 'list'::text, p_entry_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'file'::text, p_label text DEFAULT NULL::text, p_file_url text DEFAULT NULL::text, p_file_name text DEFAULT NULL::text, p_document_id uuid DEFAULT NULL::uuid, p_attachment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_rows jsonb;
  v_desc text;
BEGIN
  IF NOT (auth.role() = 'service_role'
          OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'approver')
          OR public.can_access_module(auth.uid(), 'accounting')) THEN
    RAISE EXCEPTION 'Only roles granted the accounting module (or admin/approver) can manage verification documents';
  END IF;

  IF p_action = 'list' THEN
    IF p_entry_id IS NULL THEN
      RETURN jsonb_build_object('error', 'entry_id is required for list');
    END IF;
    SELECT jsonb_agg(jsonb_build_object(
             'id', d.id, 'kind', d.kind, 'label', d.label,
             'file_name', d.file_name, 'file_url', d.file_url,
             'document_id', d.document_id, 'document_title', doc.title,
             'source', d.source) ORDER BY d.sort_order, d.created_at)
      INTO v_rows
      FROM public.journal_entry_documents d
      LEFT JOIN public.documents doc ON doc.id = d.document_id
     WHERE d.journal_entry_id = p_entry_id;
    RETURN jsonb_build_object(
      'entry_id', p_entry_id,
      'documents', COALESCE(v_rows, '[]'::jsonb),
      'note', CASE WHEN v_rows IS NULL
        THEN 'This verification carries no underlying documentation. BFL 5:7 wants a verification to identify what it rests on — attach the receipt, invoice or statement it was booked from.'
        ELSE 'The documents this verification rests on.' END);
  END IF;

  IF p_action = 'remove' THEN
    IF p_attachment_id IS NULL THEN
      RETURN jsonb_build_object('error', 'attachment_id is required for remove');
    END IF;
    DELETE FROM public.journal_entry_documents WHERE id = p_attachment_id;
    RETURN jsonb_build_object('removed', FOUND, 'attachment_id', p_attachment_id,
      'note', 'The attachment link is gone. A kind=document attachment only removed the LINK — the document itself is still in the archive.');
  END IF;

  IF p_action <> 'attach' THEN
    RETURN jsonb_build_object('error', format('Unknown action "%s". Use list|attach|remove', p_action));
  END IF;

  IF p_entry_id IS NULL THEN
    RETURN jsonb_build_object('error', 'entry_id is required for attach');
  END IF;
  SELECT description INTO v_desc FROM public.journal_entries WHERE id = p_entry_id;
  IF v_desc IS NULL THEN
    RETURN jsonb_build_object('error', format('No journal entry %s. Attach to a verification that exists.', p_entry_id));
  END IF;

  IF p_kind = 'document' AND p_document_id IS NULL THEN
    RETURN jsonb_build_object('error', 'kind=document needs document_id (a row in the documents archive). Use kind=file with file_url for an uploaded artifact.');
  END IF;
  IF p_kind = 'file' AND coalesce(trim(p_file_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'kind=file needs file_url. Upload the artifact first (upload_document) or pass a URL the instance can reach.');
  END IF;

  INSERT INTO public.journal_entry_documents
    (journal_entry_id, kind, label, file_url, file_name, document_id, source, uploaded_by,
     sort_order)
  VALUES (p_entry_id, p_kind, NULLIF(btrim(coalesce(p_label, '')), ''), p_file_url, p_file_name,
          p_document_id, CASE WHEN auth.role() = 'service_role' THEN 'agent' ELSE 'upload' END,
          auth.uid(),
          COALESCE((SELECT max(sort_order) + 1 FROM public.journal_entry_documents
                     WHERE journal_entry_id = p_entry_id), 0))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('attached', true, 'attachment_id', v_id, 'entry_id', p_entry_id,
    'entry_description', v_desc,
    'note', 'The verification now identifies what it rests on. Attaching does not change any amount — the entry is untouched.');
END; $function$;
