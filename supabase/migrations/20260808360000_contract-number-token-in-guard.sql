-- {{contract.number}} is a first-class merge field — teach the guard, not just
-- the renderer.
--
-- create_contract_from_template already renders {{contract.number}} (and its
-- legacy alias [AVTALSNR]) to the freshly-minted agreement number — proven live
-- (a rendered draft shows "Avtalsnummer: AGR-2026-00017"). But the authoring
-- guard `_contract_template_unrendered_tokens` never listed it, so a template
-- that used {{contract.number}} was falsely flagged as carrying an unrendered
-- token. Renderer and guard are two views of ONE token set; they drifted. This
-- realigns them by adding the token to the guard's allowlist. Idempotent.
CREATE OR REPLACE FUNCTION public._contract_template_unrendered_tokens(p_body text)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(jsonb_agg(DISTINCT t[1]), '[]'::jsonb)
  FROM regexp_matches(p_body, '\{\{([^}]+)\}\}', 'g') AS t
  WHERE t[1] NOT IN ('counterparty.name','counterparty.email','today',
                     'start_date','end_date','value','currency','title',
                     'counterparty.org_number','counterparty.address',
                     'supplier.name','supplier.org_number','supplier.address',
                     'supplier.phone','supplier.email','supplier.signatory',
                     'terms_url','site_url','quote.lines',
                     'contract.number');
$$;
