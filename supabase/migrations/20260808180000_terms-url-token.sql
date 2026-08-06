-- The agreements said "published on the Supplier's website" — the platform
-- knows the website. Public Site URL (site_settings general.siteUrl, the same
-- setting every MCP skill uses for absolute links) now feeds a {{terms_url}}
-- token, so the signed agreement carries the actual address of the terms the
-- customer is bound by. Unset URL degrades to readable prose, never a broken
-- link: a missing value must look like words, not like markup.

CREATE OR REPLACE FUNCTION public.create_contract_from_template(
  p_template_id uuid,
  p_counterparty_name text,
  p_counterparty_email text DEFAULT NULL,
  p_overrides jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE (contract_id uuid, title text, status public.contract_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl public.contract_templates%ROWTYPE;
  v_body text;
  v_title text;
  v_start date;
  v_end date;
  v_value bigint;
  v_currency text;
  v_company_id uuid;
  v_org text;
  v_site_url text;
  v_new_id uuid;
BEGIN
  SELECT * INTO v_tpl FROM public.contract_templates WHERE id = p_template_id;
  IF v_tpl.id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_id;
  END IF;

  v_start := COALESCE((p_overrides->>'start_date')::date, CURRENT_DATE);
  v_end := NULLIF(p_overrides->>'end_date', '')::date;
  v_value := COALESCE((p_overrides->>'value_cents')::bigint, v_tpl.default_value_cents);
  v_currency := COALESCE(p_overrides->>'currency', v_tpl.default_currency);
  v_title := COALESCE(p_overrides->>'title', v_tpl.name || ' — ' || p_counterparty_name);

  v_company_id := CASE WHEN (p_overrides->>'company_id') ~* '^[0-9a-f-]{36}$'
                       THEN (p_overrides->>'company_id')::uuid END;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.companies
    WHERE lower(name) = lower(trim(p_counterparty_name)) LIMIT 1;
  END IF;

  v_org := COALESCE(
    NULLIF(trim(p_overrides->>'org_number'), ''),
    (SELECT org_number FROM public.companies WHERE id = v_company_id)
  );

  -- The canonical public URL — the setting FlowPilot and the MCP skills
  -- already use for absolute links.
  SELECT NULLIF(trim(value->>'siteUrl'), '') INTO v_site_url
  FROM public.site_settings WHERE key = 'general';

  v_body := v_tpl.body_markdown;
  v_body := replace(v_body, '{{counterparty.name}}', p_counterparty_name);
  v_body := replace(v_body, '{{counterparty.email}}', COALESCE(p_counterparty_email, ''));
  v_body := replace(v_body, '{{today}}', to_char(CURRENT_DATE, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{start_date}}', to_char(v_start, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{end_date}}', COALESCE(to_char(v_end, 'YYYY-MM-DD'), 'TBD'));
  v_body := replace(v_body, '{{value}}', to_char(v_value / 100.0, 'FM999G999G999D00'));
  v_body := replace(v_body, '{{currency}}', v_currency);
  v_body := replace(v_body, '{{title}}', v_title);

  IF v_org IS NOT NULL THEN
    v_body := replace(v_body, '{{counterparty.org_number}}', v_org);
    v_body := replace(v_body, '[KUNDENS ORGNR]', v_org);
  END IF;
  v_body := replace(v_body, '{{counterparty.org_number}}', '[KUNDENS ORGNR]');

  IF v_site_url IS NOT NULL THEN
    v_body := replace(v_body, '{{terms_url}}', rtrim(v_site_url, '/') || '/villkor');
    v_body := replace(v_body, '{{site_url}}', rtrim(v_site_url, '/'));
  END IF;
  -- Unset site URL: readable prose, never leftover markup.
  v_body := replace(v_body, '{{terms_url}}', 'Leverantörens webbplats');
  v_body := replace(v_body, '{{site_url}}', 'Leverantörens webbplats');

  INSERT INTO public.contracts
    (title, counterparty_name, counterparty_email, contract_type, status,
     company_id, start_date, end_date, value_cents, currency,
     renewal_type, renewal_notice_days,
     body_markdown, body_updated_at, template_id, version)
  VALUES
    (v_title, p_counterparty_name, p_counterparty_email, v_tpl.contract_type, 'draft',
     v_company_id, v_start, v_end, v_value, v_currency,
     v_tpl.default_renewal_type, v_tpl.default_renewal_notice_days,
     v_body, now(), p_template_id, 1)
  RETURNING id INTO v_new_id;

  RETURN QUERY SELECT c.id, c.title, c.status FROM public.contracts c WHERE c.id = v_new_id;
END;
$$;

-- Keep the authoring skill's token validator in step with the renderer: the
-- two lists drifting apart is how an agent gets told a renderable token will
-- "survive into the signed agreement".
CREATE OR REPLACE FUNCTION public._contract_template_unrendered_tokens(p_body text)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(jsonb_agg(DISTINCT t[1]), '[]'::jsonb)
  FROM regexp_matches(p_body, '\{\{([^}]+)\}\}', 'g') AS t
  WHERE t[1] NOT IN ('counterparty.name','counterparty.email','today',
                     'start_date','end_date','value','currency','title',
                     'counterparty.org_number','terms_url','site_url');
$$;


-- manage_contract_template re-created here (migrations are append-only — the
-- original 20260807 file stays untouched so fresh installs replay cleanly)
-- with its validator delegated to the shared list above. One token list,
-- shared by the authoring skill and the renderer.
CREATE OR REPLACE FUNCTION public.manage_contract_template(
  p_action text,
  p_template text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_contract_type text DEFAULT NULL,
  p_language text DEFAULT NULL,
  p_body_markdown text DEFAULT NULL,
  p_currency text DEFAULT NULL,
  p_renewal_type text DEFAULT NULL,
  p_renewal_notice_days integer DEFAULT NULL,
  p_value_cents bigint DEFAULT NULL,
  p_is_default boolean DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_row public.contract_templates%ROWTYPE;
  v_type public.contract_type;
  v_renewal public.renewal_type;
  v_valid_types text;
BEGIN
  -- The MCP gateway runs RPC skills with the service key, so auth.uid() is NULL
  -- inside this function — without the service_role escape an operator only
  -- ever sees "Only admins…".
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Only admins can manage contract templates';
  END IF;

  SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder) INTO v_valid_types
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'contract_type';

  -- ── Resolve an existing template: id, or name (exact then unique prefix) ──
  IF p_template IS NOT NULL AND trim(p_template) <> '' THEN
    SELECT * INTO v_row FROM public.contract_templates
    WHERE id = CASE WHEN p_template ~* '^[0-9a-f-]{36}$' THEN p_template::uuid END
    LIMIT 1;

    IF v_row.id IS NULL THEN
      SELECT * INTO v_row FROM public.contract_templates
      WHERE lower(name) = lower(trim(p_template)) LIMIT 1;
    END IF;

    IF v_row.id IS NULL THEN
      -- Unique prefix only. Ambiguity must be an error, never a silent pick —
      -- editing the wrong agreement body is not something a retry reveals.
      IF (SELECT count(*) FROM public.contract_templates
          WHERE lower(name) LIKE lower(trim(p_template)) || '%') = 1 THEN
        SELECT * INTO v_row FROM public.contract_templates
        WHERE lower(name) LIKE lower(trim(p_template)) || '%' LIMIT 1;
      ELSIF (SELECT count(*) FROM public.contract_templates
             WHERE lower(name) LIKE lower(trim(p_template)) || '%') > 1 THEN
        RETURN jsonb_build_object('error',
          'Several templates start with "' || p_template || '": ' ||
          (SELECT string_agg(name, ' | ' ORDER BY name) FROM public.contract_templates
           WHERE lower(name) LIKE lower(trim(p_template)) || '%') ||
          '. Pass the full name or the id.');
      END IF;
    END IF;
  END IF;

  -- ── get ──────────────────────────────────────────────────────────────────
  IF p_action = 'get' THEN
    IF v_row.id IS NULL THEN
      RETURN jsonb_build_object('error',
        'Template not found: ' || COALESCE(p_template, '(none passed)') ||
        '. Run list_contract_templates to see the names.');
    END IF;
    RETURN jsonb_build_object(
      'id', v_row.id, 'name', v_row.name, 'description', v_row.description,
      'contract_type', v_row.contract_type, 'language', v_row.language,
      'body_markdown', v_row.body_markdown, 'currency', v_row.default_currency,
      'renewal_type', v_row.default_renewal_type,
      'renewal_notice_days', v_row.default_renewal_notice_days,
      'value_cents', v_row.default_value_cents,
      'is_default', v_row.is_default, 'is_active', v_row.is_active);

  -- ── create ───────────────────────────────────────────────────────────────
  ELSIF p_action = 'create' THEN
    IF p_name IS NULL OR trim(p_name) = '' THEN
      RETURN jsonb_build_object('error', 'name is required for create');
    END IF;
    IF p_body_markdown IS NULL OR trim(p_body_markdown) = '' THEN
      RETURN jsonb_build_object('error',
        'body_markdown is required for create — a template with no body would produce blank agreements.');
    END IF;

    -- Idempotent for agents that retry: an existing name returns that row
    -- rather than a duplicate-key error they would read as "cannot create".
    SELECT * INTO v_row FROM public.contract_templates
    WHERE lower(name) = lower(trim(p_name)) LIMIT 1;
    IF v_row.id IS NOT NULL THEN
      RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
        'already_existed', true,
        'hint', 'Use action=update to change the body of an existing template.');
    END IF;

    BEGIN
      v_type := COALESCE(NULLIF(trim(p_contract_type), ''), 'service')::public.contract_type;
    EXCEPTION WHEN others THEN
      RETURN jsonb_build_object('error',
        'Unknown contract_type "' || p_contract_type || '". Valid: ' || v_valid_types);
    END;
    BEGIN
      v_renewal := COALESCE(NULLIF(trim(p_renewal_type), ''), 'manual')::public.renewal_type;
    EXCEPTION WHEN others THEN
      RETURN jsonb_build_object('error',
        'Unknown renewal_type "' || p_renewal_type || '". Valid: none, auto, manual');
    END;

    INSERT INTO public.contract_templates
      (name, description, contract_type, language, body_markdown, default_currency,
       default_renewal_type, default_renewal_notice_days, default_value_cents,
       is_default, is_active, created_by)
    VALUES (trim(p_name), NULLIF(trim(p_description), ''), v_type,
            COALESCE(NULLIF(trim(p_language), ''), 'sv'), p_body_markdown,
            COALESCE(NULLIF(trim(p_currency), ''), 'SEK'),
            v_renewal, COALESCE(p_renewal_notice_days, 90), p_value_cents,
            COALESCE(p_is_default, false), COALESCE(p_is_active, true),
            COALESCE(auth.uid(),
                     (SELECT user_id FROM public.user_roles WHERE role = 'admin'
                      ORDER BY created_at LIMIT 1)))
    RETURNING * INTO v_row;

    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
      'contract_type', v_row.contract_type, 'language', v_row.language,
      'body_length', length(v_row.body_markdown),
      'unrendered_tokens', public._contract_template_unrendered_tokens(v_row.body_markdown),
      'already_existed', false);

  -- ── update ───────────────────────────────────────────────────────────────
  ELSIF p_action = 'update' THEN
    IF v_row.id IS NULL THEN
      RETURN jsonb_build_object('error',
        'Template not found: ' || COALESCE(p_template, '(none passed)') ||
        '. Pass template = the exact name or id.');
    END IF;
    IF p_body_markdown IS NOT NULL AND trim(p_body_markdown) = '' THEN
      RETURN jsonb_build_object('error',
        'Refusing to blank body_markdown. Omit the field to leave it unchanged.');
    END IF;

    IF p_contract_type IS NOT NULL AND trim(p_contract_type) <> '' THEN
      BEGIN
        v_type := trim(p_contract_type)::public.contract_type;
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('error',
          'Unknown contract_type "' || p_contract_type || '". Valid: ' || v_valid_types);
      END;
    ELSE
      v_type := v_row.contract_type;
    END IF;

    IF p_renewal_type IS NOT NULL AND trim(p_renewal_type) <> '' THEN
      BEGIN
        v_renewal := trim(p_renewal_type)::public.renewal_type;
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('error',
          'Unknown renewal_type "' || p_renewal_type || '". Valid: none, auto, manual');
      END;
    ELSE
      v_renewal := v_row.default_renewal_type;
    END IF;

    UPDATE public.contract_templates SET
      name = COALESCE(NULLIF(trim(p_name), ''), name),
      description = COALESCE(NULLIF(trim(p_description), ''), description),
      contract_type = v_type,
      language = COALESCE(NULLIF(trim(p_language), ''), language),
      body_markdown = COALESCE(p_body_markdown, body_markdown),
      default_currency = COALESCE(NULLIF(trim(p_currency), ''), default_currency),
      default_renewal_type = v_renewal,
      default_renewal_notice_days = COALESCE(p_renewal_notice_days, default_renewal_notice_days),
      default_value_cents = COALESCE(p_value_cents, default_value_cents),
      is_default = COALESCE(p_is_default, is_default),
      is_active = COALESCE(p_is_active, is_active),
      updated_at = now()
    WHERE id = v_row.id
    RETURNING * INTO v_row;

    -- Read the row back. A status that describes the intention rather than the
    -- stored row is how a silent no-op passes for a successful write.
    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
      'contract_type', v_row.contract_type, 'language', v_row.language,
      'body_length', length(v_row.body_markdown),
      'is_active', v_row.is_active, 'updated', true);

  -- ── archive ──────────────────────────────────────────────────────────────
  -- Deactivate, never DELETE: contracts already created from a template keep
  -- their own rendered body, but the template row is the provenance of every
  -- agreement signed from it.
  ELSIF p_action IN ('archive', 'delete') THEN
    IF v_row.id IS NULL THEN
      RETURN jsonb_build_object('error',
        'Template not found: ' || COALESCE(p_template, '(none passed)'));
    END IF;
    UPDATE public.contract_templates SET is_active = false, updated_at = now()
    WHERE id = v_row.id RETURNING * INTO v_row;
    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
      'is_active', v_row.is_active, 'archived', true,
      'note', 'Templates are archived, not deleted — they are the provenance of every contract signed from them. Set is_active = true to restore.');

  ELSE
    RETURN jsonb_build_object('error',
      'Unknown action "' || COALESCE(p_action, '(null)') || '". Use get, create, update or archive.');
  END IF;
END;
$$;
