-- Business Identity belongs to the people who own the message.
--
-- Decision (Magnus, 2026-08-13): Business Identity moves out of the admin-only
-- nav group so sales, accounting and marketing can read AND edit it. The page
-- is two things sharing a URL — legal formalia and the go-to-market message
-- (ICP, value proposition, differentiators, services) — and the second half is
-- sales/marketing craft, not administration. It is also the grounding for
-- everything the AI says outward (fit analysis, intro letters, chat), and when
-- prospecting, being able to refine what you can read yourself matters. A
-- split into formalia (admin) vs message (matrix-gated) is deliberately saved
-- for later; transparency first.
--
-- The nav's group placement had already drifted into a lie: the matrix granted
-- companyInsights to sales from the start, but the page sat in the adminOnly
-- group — the one group gate that silences module-bearing items. Same class as
-- the Profile bug. The nav fix is in code; this migration opens the WRITE path
-- with the narrowest possible policy: exactly one site_settings row.
--
-- site_settings also holds modules, integrations, demo_mode — the keys that
-- run the instance. The policy is therefore keyed to 'company_profile' alone;
-- module access buys you the company story, nothing else.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'site_settings'
       AND policyname = 'Company profile editable by its module roles'
  ) THEN
    CREATE POLICY "Company profile editable by its module roles" ON public.site_settings
      FOR UPDATE
      USING (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'))
      WITH CHECK (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'site_settings'
       AND policyname = 'Company profile creatable by its module roles'
  ) THEN
    CREATE POLICY "Company profile creatable by its module roles" ON public.site_settings
      FOR INSERT
      WITH CHECK (key = 'company_profile' AND can_access_module(auth.uid(), 'companyInsights'));
  END IF;
END $$;

-- The grant: sales had companyInsights since the original seeds; accounting
-- and marketing join (invoicing identity and campaign identity respectively).
-- Insert-if-absent, so a deliberate revocation survives.
DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['sales', 'accounting', 'marketing'] LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT r::app_role, 'companyInsights'
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = r::app_role AND x.module_id = 'companyInsights'
     );
    INSERT INTO public.role_module_access (role, module_id)
    SELECT r::app_role, 'companyInsights'
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = r::app_role AND x.module_id = 'companyInsights'
     );
  END LOOP;
END $$;
