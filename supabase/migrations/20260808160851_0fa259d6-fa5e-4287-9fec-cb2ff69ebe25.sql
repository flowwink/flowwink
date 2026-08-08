ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS quote_id uuid REFERENCES public.quotes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS contract_number text;

CREATE INDEX IF NOT EXISTS contracts_quote_id_idx
  ON public.contracts (quote_id) WHERE quote_id IS NOT NULL;

COMMENT ON COLUMN public.contracts.quote_id IS
  'The quote this agreement was drafted from, when there was one. Reaches deal_id and lead_id through quotes, so one link is enough. Nullable: contracts are also written directly.';
COMMENT ON COLUMN public.contracts.contract_number IS
  'AGR-YYYY-NNNNN from next_document_number(''contract'', ''AGR''). Assigned by trigger on insert when not supplied. NOT the CTR- series, which numbers contract BILLING invoices.';

CREATE OR REPLACE FUNCTION public.assign_contract_number()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.contract_number IS NULL OR trim(NEW.contract_number) = '' THEN
    NEW.contract_number := public.next_document_number('contract', 'AGR');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contracts_assign_number ON public.contracts;
CREATE TRIGGER contracts_assign_number
  BEFORE INSERT ON public.contracts
  FOR EACH ROW EXECUTE FUNCTION public.assign_contract_number();

DO $$
DECLARE v_max bigint;
BEGIN
  WITH numbered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS n
    FROM public.contracts WHERE contract_number IS NULL
  )
  UPDATE public.contracts c
  SET contract_number = 'AGR-' || to_char(COALESCE(c.created_at, now()), 'YYYY')
                        || '-' || lpad(numbered.n::text, 5, '0')
  FROM numbered WHERE numbered.id = c.id;

  SELECT count(*) INTO v_max FROM public.contracts;
  IF v_max > 0 THEN
    INSERT INTO public.document_number_counters(kind, prefix, last_value)
    VALUES ('contract', 'AGR', v_max)
    ON CONFLICT (kind) DO UPDATE
      SET last_value = GREATEST(public.document_number_counters.last_value, EXCLUDED.last_value),
          prefix = EXCLUDED.prefix;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS contracts_contract_number_key
  ON public.contracts (contract_number) WHERE contract_number IS NOT NULL;

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

UPDATE public.quotes q
SET company_id = l.company_id
FROM public.deals d
JOIN public.leads l ON l.id = d.lead_id
WHERE q.deal_id = d.id AND q.company_id IS NULL AND l.company_id IS NOT NULL;

UPDATE public.contracts c
SET company_id = q.company_id
FROM public.quotes q
WHERE c.quote_id = q.id AND c.company_id IS NULL AND q.company_id IS NOT NULL;