ALTER TABLE public.inbound_email_accounts
  ADD COLUMN IF NOT EXISTS route_mode text NOT NULL DEFAULT 'crm_only';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'inbound_email_accounts_route_mode_check'
  ) THEN
    ALTER TABLE public.inbound_email_accounts
      ADD CONSTRAINT inbound_email_accounts_route_mode_check
      CHECK (route_mode IN ('crm_only','crm_then_ticket','ticket_only'));
  END IF;
END $$;