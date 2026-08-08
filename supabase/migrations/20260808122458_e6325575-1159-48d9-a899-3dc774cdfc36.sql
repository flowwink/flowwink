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
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_row contract_templates;
  v_id uuid;
  v_matches int;
  v_tokens text[];
  v_allowed text[] := ARRAY['counterparty.name','counterparty.email','today','start_date','end_date','value','currency','title'];
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Only admins can manage contract templates';
  END IF;

  IF p_template IS NOT NULL AND p_action IN ('get','update','archive') THEN
    BEGIN
      v_id := p_template::uuid;
    EXCEPTION WHEN others THEN
      v_id := NULL;
    END;
    IF v_id IS NOT NULL THEN
      SELECT * INTO v_row FROM contract_templates WHERE id = v_id;
    ELSE
      SELECT * INTO v_row FROM contract_templates WHERE lower(name) = lower(p_template);
      IF NOT FOUND THEN
        SELECT count(*) INTO v_matches FROM contract_templates WHERE name ILIKE p_template || '%';
        IF v_matches > 1 THEN
          RAISE EXCEPTION 'Template name "%" is ambiguous. Candidates: %', p_template,
            (SELECT string_agg(name, ', ' ORDER BY name) FROM contract_templates WHERE name ILIKE p_template || '%');
        END IF;
        SELECT * INTO v_row FROM contract_templates WHERE name ILIKE p_template || '%';
      END IF;
    END IF;
    IF v_row.id IS NULL THEN
      RAISE EXCEPTION 'Template "%" not found', p_template;
    END IF;
  END IF;

  IF p_action = 'get' THEN
    IF p_template IS NULL THEN RAISE EXCEPTION 'get requires p_template'; END IF;
    RETURN jsonb_build_object('template', to_jsonb(v_row));

  ELSIF p_action = 'create' THEN
    IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'create requires p_name'; END IF;
    IF p_body_markdown IS NULL OR btrim(p_body_markdown) = '' THEN
      RAISE EXCEPTION 'create requires p_body_markdown (the full agreement text in Markdown)';
    END IF;

    SELECT * INTO v_row FROM contract_templates WHERE lower(name) = lower(btrim(p_name));
    IF FOUND THEN
      RETURN jsonb_build_object('created', false, 'already_existed', true, 'template_id', v_row.id, 'template', to_jsonb(v_row));
    END IF;

    INSERT INTO contract_templates (
      name, description, contract_type, language, body_markdown,
      default_currency, default_renewal_type, default_renewal_notice_days,
      default_value_cents, is_default, is_active, created_by
    ) VALUES (
      btrim(p_name), p_description,
      coalesce(p_contract_type, 'service')::contract_type,
      coalesce(p_language, 'sv'),
      p_body_markdown,
      coalesce(p_currency, 'SEK'),
      coalesce(p_renewal_type, 'none')::renewal_type,
      coalesce(p_renewal_notice_days, 90),
      coalesce(p_value_cents, 0),
      coalesce(p_is_default, false),
      coalesce(p_is_active, true),
      auth.uid()
    ) RETURNING * INTO v_row;

    SELECT coalesce(array_agg(DISTINCT m.t), ARRAY[]::text[]) INTO v_tokens
    FROM (SELECT btrim((regexp_matches(p_body_markdown, '\{\{([^}]+)\}\}', 'g'))[1]) AS t) m
    WHERE m.t <> ALL (v_allowed);

    RETURN jsonb_build_object('created', true, 'template_id', v_row.id, 'template', to_jsonb(v_row), 'unrendered_tokens', to_jsonb(v_tokens));

  ELSIF p_action = 'update' THEN
    IF p_template IS NULL THEN RAISE EXCEPTION 'update requires p_template'; END IF;
    IF p_body_markdown IS NOT NULL AND btrim(p_body_markdown) = '' THEN
      RAISE EXCEPTION 'p_body_markdown cannot be blanked - omit it to leave the body unchanged';
    END IF;

    UPDATE contract_templates SET
      name = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
      description = coalesce(p_description, description),
      contract_type = coalesce(p_contract_type::contract_type, contract_type),
      language = coalesce(p_language, language),
      body_markdown = coalesce(p_body_markdown, body_markdown),
      default_currency = coalesce(p_currency, default_currency),
      default_renewal_type = coalesce(p_renewal_type::renewal_type, default_renewal_type),
      default_renewal_notice_days = coalesce(p_renewal_notice_days, default_renewal_notice_days),
      default_value_cents = coalesce(p_value_cents, default_value_cents),
      is_default = coalesce(p_is_default, is_default),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    WHERE id = v_row.id
    RETURNING * INTO v_row;

    SELECT coalesce(array_agg(DISTINCT m.t), ARRAY[]::text[]) INTO v_tokens
    FROM (SELECT btrim((regexp_matches(v_row.body_markdown, '\{\{([^}]+)\}\}', 'g'))[1]) AS t) m
    WHERE m.t <> ALL (v_allowed);

    RETURN jsonb_build_object('updated', true, 'template_id', v_row.id, 'template', to_jsonb(v_row), 'unrendered_tokens', to_jsonb(v_tokens));

  ELSIF p_action = 'archive' THEN
    IF p_template IS NULL THEN RAISE EXCEPTION 'archive requires p_template'; END IF;
    UPDATE contract_templates SET is_active = false, is_default = false, updated_at = now()
      WHERE id = v_row.id RETURNING * INTO v_row;
    RETURN jsonb_build_object('archived', true, 'template_id', v_row.id);
  END IF;

  RAISE EXCEPTION 'Unknown action %. Use get|create|update|archive', p_action;
END; $fn$;

GRANT EXECUTE ON FUNCTION public.manage_contract_template(text, text, text, text, text, text, text, text, text, integer, bigint, boolean, boolean) TO authenticated, service_role;