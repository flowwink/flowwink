-- Appendices: what the agreement REFERENCES must be something the agreement HOLDS.
--
-- Every service agreement FlowWink renders says "enligt Bilaga 1" and defines a
-- precedence order (main document > Bilaga 1 > general terms) — and until now
-- nothing could attach. The agent-authored templates made the gap visible in
-- production data: three fresh agreements promising a Bilaga the system could
-- not hold.
--
-- Design:
--   * ONE register, not two. contract_documents (an empty shell — 0 rows on the
--     whole fleet, no UI writer) becomes the appendix register, keeping the
--     list_contract_documents skill name that already points at it.
--   * TWO kinds, one numbered list the customer sees:
--       kind='file'      — an uploaded PDF/DOCX (a spec, a drawing, a price list)
--       kind='document'  — markdown, typically rendered from an appendix
--                          contract_template (DPA, third-party acknowledgement,
--                          power of attorney)
--     The customer must not have to understand which is which.
--   * The LABEL is the join between prose and object: the body says "Bilaga 1",
--     so the register carries that exact wording.

-- ── the register ────────────────────────────────────────────────────────────
-- A markdown appendix has no file, so the file columns can no longer be NOT
-- NULL. Safe: the table is empty everywhere.
ALTER TABLE public.contract_documents ALTER COLUMN file_name DROP NOT NULL;
ALTER TABLE public.contract_documents ALTER COLUMN file_url  DROP NOT NULL;

ALTER TABLE public.contract_documents
  ADD COLUMN IF NOT EXISTS label text,
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'file',
  ADD COLUMN IF NOT EXISTS body_markdown text,
  ADD COLUMN IF NOT EXISTS template_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_documents_kind_chk') THEN
    ALTER TABLE public.contract_documents ADD CONSTRAINT contract_documents_kind_chk
      CHECK (kind IN ('file', 'document'));
  END IF;
  -- An appendix must actually contain something: a file needs a URL, a
  -- document needs a body. Half-created appendices are the failure mode this
  -- whole migration exists to remove.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_documents_content_chk') THEN
    ALTER TABLE public.contract_documents ADD CONSTRAINT contract_documents_content_chk
      CHECK (
        (kind = 'file' AND file_url IS NOT NULL)
        OR (kind = 'document' AND coalesce(trim(body_markdown), '') <> '')
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS contract_documents_contract_order_idx
  ON public.contract_documents(contract_id, sort_order);

-- ── writes are staff-only; reads stay as they are ───────────────────────────
-- An appendix is part of a signed agreement, so "any authenticated user may
-- insert" is too wide. The public/customer path never touches the table
-- directly — it goes through the SECURITY DEFINER token RPC below.
DROP POLICY IF EXISTS "Authenticated users can create contract documents" ON public.contract_documents;
DROP POLICY IF EXISTS "Authenticated users can delete contract documents" ON public.contract_documents;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='contract_documents' AND policyname='Staff manage contract appendices') THEN
    CREATE POLICY "Staff manage contract appendices" ON public.contract_documents
      FOR ALL TO authenticated
      USING (is_staff(auth.uid()))
      WITH CHECK (is_staff(auth.uid()));
  END IF;
END $$;

-- ── manage_contract_appendix ────────────────────────────────────────────────
-- One entry point for the whole register. from_template renders an appendix
-- contract_template into a document appendix, so the same authoring guide that
-- teaches an agent to WRITE an appendix lets it ATTACH one.
CREATE OR REPLACE FUNCTION public.manage_contract_appendix(
  p_action text,
  p_contract_id uuid DEFAULT NULL,
  p_appendix_id uuid DEFAULT NULL,
  p_label text DEFAULT NULL,
  p_title text DEFAULT NULL,
  p_body_markdown text DEFAULT NULL,
  p_file_url text DEFAULT NULL,
  p_file_name text DEFAULT NULL,
  p_file_type text DEFAULT NULL,
  p_template text DEFAULT NULL,
  p_sort_order integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_order integer;
  v_kind text;
  v_body text;
  v_title text;
  v_tpl public.contract_templates%ROWTYPE;
  v_id uuid;
  v_result jsonb;
BEGIN
  IF NOT (auth.role() = 'service_role' OR is_staff(auth.uid())) THEN
    RAISE EXCEPTION 'Only staff can manage contract appendices';
  END IF;

  IF p_action = 'list' THEN
    IF p_contract_id IS NULL THEN
      RAISE EXCEPTION 'contract_id is required for action=list';
    END IF;
    SELECT jsonb_build_object('count', count(*), 'appendices', coalesce(jsonb_agg(
             jsonb_build_object('id', d.id, 'label', d.label, 'title', d.title,
                                'kind', d.kind, 'sort_order', d.sort_order,
                                'file_name', d.file_name, 'file_url', d.file_url,
                                'has_body', d.body_markdown IS NOT NULL)
             ORDER BY d.sort_order), '[]'::jsonb))
      INTO v_result
      FROM public.contract_documents d WHERE d.contract_id = p_contract_id;
    RETURN v_result;
  END IF;

  IF p_action = 'delete' THEN
    DELETE FROM public.contract_documents WHERE id = p_appendix_id;
    RETURN jsonb_build_object('deleted', p_appendix_id);
  END IF;

  IF p_action = 'update' THEN
    UPDATE public.contract_documents
       SET label = coalesce(p_label, label),
           title = coalesce(p_title, title),
           body_markdown = coalesce(p_body_markdown, body_markdown),
           sort_order = coalesce(p_sort_order, sort_order)
     WHERE id = p_appendix_id
     RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Appendix not found: %', p_appendix_id; END IF;
    RETURN jsonb_build_object('id', v_id, 'updated', true);
  END IF;

  IF p_action <> 'create' THEN
    RAISE EXCEPTION 'Unknown action: % (use list, create, update or delete)', p_action;
  END IF;

  IF p_contract_id IS NULL THEN
    RAISE EXCEPTION 'contract_id is required for action=create';
  END IF;

  -- Appendices are numbered in the order they are added unless told otherwise.
  SELECT coalesce(p_sort_order, coalesce(max(sort_order), 0) + 1)
    INTO v_order FROM public.contract_documents WHERE contract_id = p_contract_id;

  IF p_template IS NOT NULL THEN
    SELECT * INTO v_tpl FROM public.contract_templates
     WHERE id::text = p_template OR lower(name) = lower(p_template)
     LIMIT 1;
    IF v_tpl.id IS NULL THEN
      RAISE EXCEPTION 'Template not found: %. Run list_contract_templates first.', p_template;
    END IF;
    v_kind := 'document';
    v_body := v_tpl.body_markdown;
    v_title := coalesce(p_title, v_tpl.name);
  ELSIF p_body_markdown IS NOT NULL AND trim(p_body_markdown) <> '' THEN
    v_kind := 'document'; v_body := p_body_markdown; v_title := p_title;
  ELSIF p_file_url IS NOT NULL THEN
    v_kind := 'file'; v_title := coalesce(p_title, p_file_name);
  ELSE
    RAISE EXCEPTION 'An appendix needs content: pass template, body_markdown or file_url';
  END IF;

  INSERT INTO public.contract_documents
    (contract_id, kind, label, title, body_markdown, file_url, file_name, file_type,
     sort_order, template_id, uploaded_by, version)
  VALUES
    (p_contract_id, v_kind, coalesce(p_label, 'Bilaga ' || v_order), v_title, v_body,
     p_file_url, p_file_name, p_file_type, v_order, v_tpl.id, auth.uid(), 1)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'label', coalesce(p_label, 'Bilaga ' || v_order),
                            'title', v_title, 'kind', v_kind, 'sort_order', v_order);
END;
$$;

GRANT EXECUTE ON FUNCTION public.manage_contract_appendix(text, uuid, uuid, text, text, text, text, text, text, text, integer)
  TO authenticated, service_role;

-- ── the customer sees them where they sign ──────────────────────────────────
-- The requirement that makes appendices real: they must be VISIBLE when the
-- customer reviews the agreement. Returning them from the same token RPC keeps
-- it to one round trip and one authorisation path.
DROP FUNCTION IF EXISTS public.get_public_contract(text);
CREATE FUNCTION public.get_public_contract(p_token text)
RETURNS TABLE(
  id uuid, title text, counterparty_name text, counterparty_email text,
  status public.contract_status, body_markdown text,
  signed_at timestamp with time zone, version integer, currency text,
  value_cents bigint, start_date date, end_date date,
  appendices jsonb
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT c.id, c.title, c.counterparty_name, c.counterparty_email, c.status,
         c.body_markdown, c.signed_at, c.version, c.currency, c.value_cents,
         c.start_date, c.end_date,
         coalesce((
           SELECT jsonb_agg(jsonb_build_object(
                    'id', d.id, 'label', d.label, 'title', d.title, 'kind', d.kind,
                    'body_markdown', d.body_markdown,
                    'file_name', d.file_name, 'file_url', d.file_url)
                  ORDER BY d.sort_order)
             FROM public.contract_documents d WHERE d.contract_id = c.id
         ), '[]'::jsonb) AS appendices
    FROM public.contracts c
   WHERE c.accept_token = p_token;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_contract(text) TO anon, authenticated, service_role;
