ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.quotes.owner_id IS
  'Owner (profiles/auth uid). Inherited on insert: explicit > deal owner > lead owner > creator. A lens and a label — never referenced by RLS.';

CREATE OR REPLACE FUNCTION public.assign_owner_on_insert()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF TG_TABLE_NAME = 'leads' THEN
    IF NEW.assigned_to IS NULL AND v_uid IS NOT NULL THEN
      NEW.assigned_to := v_uid;
    END IF;

  ELSIF TG_TABLE_NAME = 'companies' THEN
    IF NEW.account_owner IS NULL AND v_uid IS NOT NULL THEN
      NEW.account_owner := v_uid;
    END IF;

  ELSIF TG_TABLE_NAME = 'deals' THEN
    IF NEW.owner_id IS NULL AND NEW.lead_id IS NOT NULL THEN
      SELECT assigned_to INTO NEW.owner_id FROM public.leads WHERE id = NEW.lead_id;
    END IF;
    IF NEW.owner_id IS NULL AND v_uid IS NOT NULL THEN
      NEW.owner_id := v_uid;
    END IF;

  ELSIF TG_TABLE_NAME = 'quotes' THEN
    IF NEW.owner_id IS NULL AND NEW.deal_id IS NOT NULL THEN
      SELECT owner_id INTO NEW.owner_id FROM public.deals WHERE id = NEW.deal_id;
    END IF;
    IF NEW.owner_id IS NULL AND NEW.lead_id IS NOT NULL THEN
      SELECT assigned_to INTO NEW.owner_id FROM public.leads WHERE id = NEW.lead_id;
    END IF;
    IF NEW.owner_id IS NULL AND v_uid IS NOT NULL THEN
      NEW.owner_id := v_uid;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leads_assign_owner ON public.leads;
CREATE TRIGGER leads_assign_owner
  BEFORE INSERT ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.assign_owner_on_insert();

DROP TRIGGER IF EXISTS deals_assign_owner ON public.deals;
CREATE TRIGGER deals_assign_owner
  BEFORE INSERT ON public.deals
  FOR EACH ROW EXECUTE FUNCTION public.assign_owner_on_insert();

DROP TRIGGER IF EXISTS companies_assign_owner ON public.companies;
CREATE TRIGGER companies_assign_owner
  BEFORE INSERT ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.assign_owner_on_insert();

DROP TRIGGER IF EXISTS quotes_assign_owner ON public.quotes;
CREATE TRIGGER quotes_assign_owner
  BEFORE INSERT ON public.quotes
  FOR EACH ROW EXECUTE FUNCTION public.assign_owner_on_insert();

UPDATE public.leads     SET assigned_to   = created_by WHERE assigned_to   IS NULL AND created_by IS NOT NULL;
UPDATE public.deals     SET owner_id      = created_by WHERE owner_id      IS NULL AND created_by IS NOT NULL;
UPDATE public.companies SET account_owner = created_by WHERE account_owner IS NULL AND created_by IS NOT NULL;

UPDATE public.deals d SET owner_id = l.assigned_to
  FROM public.leads l
  WHERE d.owner_id IS NULL AND d.lead_id = l.id AND l.assigned_to IS NOT NULL;

UPDATE public.quotes q SET owner_id = d.owner_id
  FROM public.deals d
  WHERE q.owner_id IS NULL AND q.deal_id = d.id AND d.owner_id IS NOT NULL;

UPDATE public.quotes q SET owner_id = l.assigned_to
  FROM public.leads l
  WHERE q.owner_id IS NULL AND q.lead_id = l.id AND l.assigned_to IS NOT NULL;

UPDATE public.quotes SET owner_id = created_by
  WHERE owner_id IS NULL AND created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.ownership_delegations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  note text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ownership_delegations_not_self CHECK (from_user <> to_user),
  CONSTRAINT ownership_delegations_window CHECK (ends_on >= starts_on)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ownership_delegations TO authenticated;
GRANT ALL ON public.ownership_delegations TO service_role;

CREATE INDEX IF NOT EXISTS ownership_delegations_active_idx
  ON public.ownership_delegations (to_user, starts_on, ends_on);

ALTER TABLE public.ownership_delegations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Coverage is visible to colleagues" ON public.ownership_delegations;
CREATE POLICY "Coverage is visible to colleagues"
  ON public.ownership_delegations FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "The covered person or an admin manages coverage" ON public.ownership_delegations;
CREATE POLICY "The covered person or an admin manages coverage"
  ON public.ownership_delegations FOR ALL
  TO authenticated
  USING (from_user = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (from_user = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

COMMENT ON TABLE public.ownership_delegations IS
  'Time-boxed coverage: to_user acts for from_user between starts_on and ends_on (inclusive). Nothing is reassigned; ownership columns never move.';