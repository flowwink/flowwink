-- Cold outreach is legal in some countries and not in others — as DATA.
--
-- ePrivacy is implemented per member state, and the difference is not a detail:
-- in Sweden, Denmark, Finland, the Netherlands, France and Ireland, B2B email
-- to a business address about that business's own field is broadly allowed
-- (with an opt-out); in Germany, Italy and Austria prior consent is required
-- and the fines are real. The RECIPIENT's country governs, not the sender's.
--
-- Encoded as a lookup table, not as branches in the send path: the engine must
-- never grow `IF country = 'DE'` (localization discipline — country is data +
-- adapters behind a stable interface). Adding a country, or changing legal
-- advice, is then an UPDATE, not a deploy.
--
-- This is a decision-support gate, not a legal opinion: the seller may well
-- have consent or an existing relationship in an opt-in country. The platform's
-- job is to make sure they KNOW which regime they are in before they press
-- send, and to record that they did.

CREATE TABLE IF NOT EXISTS public.outreach_country_policy (
  country_code text PRIMARY KEY,
  country_name text NOT NULL,
  policy text NOT NULL CHECK (policy IN ('permissive', 'consent_required', 'unknown')),
  note text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.outreach_country_policy ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'outreach_country_policy' AND policyname = 'Staff can read outreach policy') THEN
    CREATE POLICY "Staff can read outreach policy" ON public.outreach_country_policy
      FOR SELECT TO authenticated USING (can_access_module(auth.uid(), 'salesIntelligence') OR can_access_module(auth.uid(), 'crm'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'outreach_country_policy' AND policyname = 'Admins maintain outreach policy') THEN
    CREATE POLICY "Admins maintain outreach policy" ON public.outreach_country_policy
      FOR ALL TO authenticated
      USING (has_role(auth.uid(), 'admin'::app_role))
      WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
  END IF;
END $$;

-- Seed: platform config (a fresh install must know the map), re-assertable but
-- never clobbering an operator's own edit — same discipline as role defaults.
INSERT INTO public.outreach_country_policy (country_code, country_name, policy, note)
SELECT * FROM (VALUES
  ('SE', 'Sweden',      'permissive',       'B2B to a business address about that business''s field is allowed with a working opt-out.'),
  ('DK', 'Denmark',     'permissive',       'B2B allowed with opt-out; keep the relevance link to the recipient''s role explicit.'),
  ('FI', 'Finland',     'permissive',       'B2B allowed with opt-out.'),
  ('NO', 'Norway',      'permissive',       'B2B allowed with opt-out (EEA, ePrivacy-aligned).'),
  ('NL', 'Netherlands', 'permissive',       'B2B allowed with opt-out; unsubscribe must work on first click.'),
  ('FR', 'France',      'permissive',       'B2B allowed to a professional address when the message concerns their profession (CNIL).'),
  ('IE', 'Ireland',     'permissive',       'B2B allowed with opt-out.'),
  ('BE', 'Belgium',     'permissive',       'B2B allowed with opt-out.'),
  ('DE', 'Germany',     'consent_required', 'UWG §7: prior consent required for B2B email. Send only with documented consent or an existing relationship.'),
  ('AT', 'Austria',     'consent_required', 'TKG §174: prior consent required.'),
  ('IT', 'Italy',       'consent_required', 'Garante: prior consent required for commercial email.'),
  ('ES', 'Spain',       'consent_required', 'LSSI: consent required unless there is a prior contractual relationship.'),
  ('CH', 'Switzerland', 'consent_required', 'UWG Art. 3(1)(o): consent required; sender identity and opt-out mandatory.'),
  ('GB', 'United Kingdom', 'permissive',    'PECR: corporate subscribers may be emailed with an opt-out; sole traders/partnerships count as individuals.'),
  ('US', 'United States', 'permissive',     'CAN-SPAM: opt-out based; a physical postal address is required in the message.')
) AS v(country_code, country_name, policy, note)
WHERE NOT EXISTS (
  SELECT 1 FROM public.outreach_country_policy p WHERE p.country_code = v.country_code
);

COMMENT ON TABLE public.outreach_country_policy IS
  'Cold-outreach regime per recipient country. Decision support for the send gate — the engine looks up, never branches. Operators may edit; new rows survive re-seeding.';
