CREATE OR REPLACE FUNCTION public._contract_template_unrendered_tokens(p_body text)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(DISTINCT t[1]), '[]'::jsonb)
  FROM regexp_matches(p_body, '\{\{([^}]+)\}\}', 'g') AS t
  WHERE t[1] NOT IN ('counterparty.name','counterparty.email','today',
                     'start_date','end_date','value','currency','title',
                     'counterparty.org_number','terms_url','site_url');
$$;

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
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Only admins can manage contract templates';
  END IF;

  SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder) INTO v_valid_types
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'contract_type';

  IF p_template IS NOT NULL AND trim(p_template) <> '' THEN
    SELECT * INTO v_row FROM public.contract_templates
    WHERE id = CASE WHEN p_template ~* '^[0-9a-f-]{36}$' THEN p_template::uuid END
    LIMIT 1;

    IF v_row.id IS NULL THEN
      SELECT * INTO v_row FROM public.contract_templates
      WHERE lower(name) = lower(trim(p_template)) LIMIT 1;
    END IF;

    IF v_row.id IS NULL THEN
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

  ELSIF p_action = 'create' THEN
    IF p_name IS NULL OR trim(p_name) = '' THEN
      RETURN jsonb_build_object('error', 'name is required for create');
    END IF;
    IF p_body_markdown IS NULL OR trim(p_body_markdown) = '' THEN
      RETURN jsonb_build_object('error',
        'body_markdown is required for create — a template with no body would produce blank agreements.');
    END IF;

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

    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
      'contract_type', v_row.contract_type, 'language', v_row.language,
      'body_length', length(v_row.body_markdown),
      'is_active', v_row.is_active, 'updated', true);

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