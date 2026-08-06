-- Company identity travels as an ID, not as prose.
--
-- AGR-2026-00005 rendered "[KUNDENS ORGNR]" while Liteit AB sat in companies
-- with org_number 556616-1658. Nothing was wrong with the data or with the
-- renderer's lookup — the CHAIN was severed: the quote was born with
-- company_id NULL (nothing fills it), so the contract inherited nothing, and
-- the last-resort name match compared 'liteit' to 'Liteit AB' and — correctly,
-- deliberately — refused to guess. A fuzzy match that puts the WRONG company's
-- org number in a legal document is far worse than a visible bracket.
--
-- The fix is not smarter matching. The ID path already exists end to end
-- (deal → lead → company; quotes.company_id; contracts.company_id) — it was
-- just never wired. Three rungs:
--
--   1. quotes: BEFORE INSERT/UPDATE trigger resolves company_id via
--      deal → lead when absent. A trigger, not dialog code, because a quote
--      is born three ways (UI dialog, manage_quote skill, RPC) and a rule
--      living in one of three places is the bug class this codebase keeps
--      refinding.
--   2. contracts: same trigger pattern, inheriting from the quote.
--   3. create_contract_from_template: resolves via the quote BEFORE building
--      the body (the trigger fires too late for tokens in the text), keeping
--      the name match strictly as last resort.
--
-- Plus a one-time backfill so existing rows join the same reality.

-- 1) Quotes inherit the company from their deal's lead.
CREATE OR REPLACE FUNCTION public.quotes_inherit_company()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.company_id IS NULL AND NEW.deal_id IS NOT NULL THEN
    SELECT l.company_id INTO NEW.company_id
    FROM public.deals d
    JOIN public.leads l ON l.id = d.lead_id
    WHERE d.id = NEW.deal_id;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS quotes_inherit_company ON public.quotes;
CREATE TRIGGER quotes_inherit_company
  BEFORE INSERT OR UPDATE OF deal_id ON public.quotes
  FOR EACH ROW EXECUTE FUNCTION public.quotes_inherit_company();

-- 2) Contracts inherit the company from their quote.
CREATE OR REPLACE FUNCTION public.contracts_inherit_company()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.company_id IS NULL AND NEW.quote_id IS NOT NULL THEN
    SELECT company_id INTO NEW.company_id
    FROM public.quotes WHERE id = NEW.quote_id;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS contracts_inherit_company ON public.contracts;
CREATE TRIGGER contracts_inherit_company
  BEFORE INSERT OR UPDATE OF quote_id ON public.contracts
  FOR EACH ROW EXECUTE FUNCTION public.contracts_inherit_company();

-- 3) Backfill, in dependency order: quotes first, then contracts through them.
UPDATE public.quotes q
SET company_id = l.company_id
FROM public.deals d
JOIN public.leads l ON l.id = d.lead_id
WHERE q.deal_id = d.id AND q.company_id IS NULL AND l.company_id IS NOT NULL;

UPDATE public.contracts c
SET company_id = q.company_id
FROM public.quotes q
WHERE c.quote_id = q.id AND c.company_id IS NULL AND q.company_id IS NOT NULL;

-- 4) The renderer resolves through the quote before falling back to the name.
CREATE OR REPLACE FUNCTION public.create_contract_from_template(
  p_template_id uuid,
  p_counterparty_name text,
  p_counterparty_email text DEFAULT NULL,
  p_overrides jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(contract_id uuid, title text, status public.contract_status)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_tpl public.contract_templates%ROWTYPE;
  v_body text;
  v_new_id uuid;
  v_start date;
  v_end date;
  v_value bigint;
  v_currency text;
  v_title text;
  v_company_id uuid;
  v_quote_id uuid;
  v_number text;
  v_org text;
  v_site_url text;
  v_profile jsonb;
  v_sup_name text;
  v_sup_org text;
  v_sup_addr text;
  v_sup_phone text;
  v_sup_email text;
  v_sup_signer text;
  v_cp_addr text;
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

  v_quote_id := CASE WHEN (p_overrides->>'quote_id') ~* '^[0-9a-f-]{36}$'
                     THEN (p_overrides->>'quote_id')::uuid END;

  v_company_id := CASE WHEN (p_overrides->>'company_id') ~* '^[0-9a-f-]{36}$'
                       THEN (p_overrides->>'company_id')::uuid END;
  -- Through the quote — the rung that was missing. AGR-2026-00005 rendered
  -- "[KUNDENS ORGNR]" with the org number sitting in companies, because the
  -- only path to it was matching 'liteit' against 'Liteit AB' by name.
  -- The quote's own company_id first, then its deal's lead, so a quote from
  -- before the inherit-trigger still resolves.
  IF v_company_id IS NULL AND v_quote_id IS NOT NULL THEN
    SELECT COALESCE(q.company_id, l.company_id) INTO v_company_id
    FROM public.quotes q
    LEFT JOIN public.deals d ON d.id = q.deal_id
    LEFT JOIN public.leads l ON l.id = d.lead_id
    WHERE q.id = v_quote_id;
  END IF;
  -- Name match stays LAST RESORT and stays exact: fuzzy-matching a company
  -- into a legal document risks the wrong company's registered data, which is
  -- far worse than a visible bracket.
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM public.companies
    WHERE lower(name) = lower(trim(p_counterparty_name)) LIMIT 1;
  END IF;

  v_org := COALESCE(
    NULLIF(trim(p_overrides->>'org_number'), ''),
    (SELECT org_number FROM public.companies WHERE id = v_company_id)
  );
  SELECT NULLIF(trim(address), '') INTO v_cp_addr
  FROM public.companies WHERE id = v_company_id;

  -- Allocated here rather than left to the trigger: the number has to appear
  -- inside the body, and the body is built before the row exists. The trigger
  -- only fills a NULL, so this wins and nothing is double-counted.
  v_number := public.next_document_number('contract', 'AGR');

  -- The canonical public URL — the setting FlowPilot and the MCP skills
  -- already use for absolute links.
  SELECT NULLIF(trim(value->>'siteUrl'), '') INTO v_site_url
  FROM public.site_settings WHERE key = 'general';

  -- ── the supplier's own master data ──────────────────────────────────────
  -- Same store the About page, the invoice footer and FlowPilot's identity all
  -- read. Registered name is preferred over display name: an agreement names
  -- the legal entity.
  SELECT value INTO v_profile FROM public.site_settings WHERE key = 'company_profile';
  v_sup_name  := COALESCE(NULLIF(trim(v_profile->>'legal_name'), ''),
                          NULLIF(trim(v_profile->>'company_name'), ''));
  v_sup_org   := NULLIF(trim(v_profile->>'org_number'), '');
  v_sup_phone := NULLIF(trim(v_profile->>'contact_phone'), '');
  v_sup_email := NULLIF(trim(v_profile->>'contact_email'), '');
  v_sup_signer := NULLIF(trim(v_profile->>'ceo'), '');
  -- Street, postal code and city are three fields and one line on paper.
  v_sup_addr := NULLIF(trim(concat_ws(', ',
    NULLIF(trim(v_profile->>'address'), ''),
    NULLIF(trim(concat_ws(' ', NULLIF(trim(v_profile->>'postal_code'), ''),
                               NULLIF(trim(v_profile->>'city'), ''))), ''),
    NULLIF(trim(v_profile->>'country'), '')
  )), '');

  v_body := v_tpl.body_markdown;
  v_body := replace(v_body, '{{counterparty.name}}', COALESCE(p_counterparty_name, ''));
  v_body := replace(v_body, '{{counterparty.email}}', COALESCE(p_counterparty_email, ''));
  v_body := replace(v_body, '{{today}}', to_char(CURRENT_DATE, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{start_date}}', to_char(v_start, 'YYYY-MM-DD'));
  v_body := replace(v_body, '{{end_date}}', COALESCE(to_char(v_end, 'YYYY-MM-DD'), 'TBD'));
  -- NULL poisons replace(): one NULL argument nulls the ENTIRE body. The UI
  -- dialog always sends value_cents so this never fired from there — but an
  -- agent calling the RPC bare, against a template with no default value,
  -- got a contract with a NULL body and a success envelope. Unknown renders
  -- as the visible bracket, per the convention everywhere else in this body.
  v_body := replace(v_body, '{{value}}',
    COALESCE(to_char(v_value / 100.0, 'FM999G999G999D00'), '[BELOPP]'));
  v_body := replace(v_body, '{{currency}}', COALESCE(v_currency, '[VALUTA]'));
  v_body := replace(v_body, '{{title}}', v_title);

  -- The agreement can finally name itself.
  v_body := replace(v_body, '{{contract.number}}', v_number);
  v_body := replace(v_body, '[AVTALSNR]', v_number);

  IF v_org IS NOT NULL THEN
    v_body := replace(v_body, '{{counterparty.org_number}}', v_org);
    v_body := replace(v_body, '[KUNDENS ORGNR]', v_org);
  END IF;
  v_body := replace(v_body, '{{counterparty.org_number}}', '[KUNDENS ORGNR]');

  IF v_cp_addr IS NOT NULL THEN
    v_body := replace(v_body, '{{counterparty.address}}', v_cp_addr);
    v_body := replace(v_body, '[KUNDENS ADRESS]', v_cp_addr);
  END IF;
  v_body := replace(v_body, '{{counterparty.address}}', '[KUNDENS ADRESS]');

  -- Supplier side. Each guarded on its own: a profile filled in halfway should
  -- contribute the half it has, not nothing.
  IF v_sup_name IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.name}}', v_sup_name);
    v_body := replace(v_body, '[LEVERANTÖRENS FIRMA]', v_sup_name);
  END IF;
  IF v_sup_org IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.org_number}}', v_sup_org);
    v_body := replace(v_body, '[ORGNR]', v_sup_org);
  END IF;
  IF v_sup_addr IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.address}}', v_sup_addr);
    v_body := replace(v_body, '[ADRESS]', v_sup_addr);
  END IF;
  IF v_sup_phone IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.phone}}', v_sup_phone);
    v_body := replace(v_body, '[TELEFON]', v_sup_phone);
  END IF;
  IF v_sup_email IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.email}}', v_sup_email);
    v_body := replace(v_body, '[E-POST]', v_sup_email);
  END IF;
  IF v_sup_signer IS NOT NULL THEN
    v_body := replace(v_body, '{{supplier.signatory}}', v_sup_signer);
    v_body := replace(v_body, '[NAMN]', v_sup_signer);
  END IF;

  -- Anything still unresolved keeps its placeholder rather than going blank —
  -- the whole point. A signer must be able to see what is missing.
  v_body := replace(v_body, '{{supplier.name}}', '[LEVERANTÖRENS FIRMA]');
  v_body := replace(v_body, '{{supplier.org_number}}', '[ORGNR]');
  v_body := replace(v_body, '{{supplier.address}}', '[ADRESS]');
  v_body := replace(v_body, '{{supplier.phone}}', '[TELEFON]');
  v_body := replace(v_body, '{{supplier.email}}', '[E-POST]');
  v_body := replace(v_body, '{{supplier.signatory}}', '[NAMN]');

  IF v_site_url IS NOT NULL THEN
    v_body := replace(v_body, '{{terms_url}}', rtrim(v_site_url, '/') || '/villkor');
    v_body := replace(v_body, '{{site_url}}', rtrim(v_site_url, '/'));
  END IF;
  -- Unset site URL: readable prose, never leftover markup.
  v_body := replace(v_body, '{{terms_url}}', 'Leverantörens webbplats');
  v_body := replace(v_body, '{{site_url}}', 'Leverantörens webbplats');

  INSERT INTO public.contracts
    (title, counterparty_name, counterparty_email, contract_type, status,
     company_id, quote_id, contract_number, start_date, end_date, value_cents, currency,
     renewal_type, renewal_notice_days,
     body_markdown, body_updated_at, template_id, version)
  VALUES
    (v_title, p_counterparty_name, p_counterparty_email, v_tpl.contract_type, 'draft',
     v_company_id, v_quote_id, v_number, v_start, v_end, v_value, v_currency,
     v_tpl.default_renewal_type, v_tpl.default_renewal_notice_days,
     v_body, now(), p_template_id, 1)
  RETURNING id INTO v_new_id;

  RETURN QUERY SELECT c.id, c.title, c.status FROM public.contracts c WHERE c.id = v_new_id;
END;
$$;

