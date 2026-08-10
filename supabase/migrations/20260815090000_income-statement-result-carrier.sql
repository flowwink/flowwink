-- The account that carries the year's result is not a line on the income
-- statement — and which account that is belongs to the chart, not the engine.
--
-- A closing entry books the year's result onto a P&L-side account (BAS 2024:
-- 8999 "Årets resultat") and credits equity. Our income statement summed every
-- P&L account, so the carrier came in as an ordinary expense and cancelled the
-- result it was carrying. LiteIT 2024: income 26 172,11, expenses 26 172,11,
-- net 0 — against an årsredovisning saying +19 537,11. 2025 the same, net 0
-- against −16 344,35. The number is not off by a bit; it is gone, and the
-- report looks perfectly balanced while it happens.
--
-- Hardcoding 8999 would fix LiteIT and break the next company. This is the same
-- shape as the VAT box map (account_tax_boxes, 2026-08-09): a CLASSIFICATION
-- that reads like engine logic but is a property of the chart of accounts. So
-- it goes in data:
--
--   account_statement_sections  — which accounts form which line of a statement.
--                                 Multi-account by design: BAS has both 8990
--                                 "Resultat" and 8999, and tax spans 8910–8980.
--   account_roles.year_result   — the SINGLE account a closing entry posts TO.
--                                 A posting target, which is what roles are for,
--                                 and the fallback the report uses on instances
--                                 that have the role but not yet the table.
--
-- Not every chart has a carrier. An IFRS chart closes the P&L straight to
-- retained earnings, so ifrs-generic maps neither the role nor the section —
-- "there is none" is a correct answer here, not a gap, and the report treats it
-- as one.

-- ── The statement section map ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_statement_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  locale text NOT NULL,
  section text NOT NULL,
  account_code text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (locale, section, account_code)
);

COMMENT ON TABLE public.account_statement_sections IS
  'Account → statement section per accounting locale. Sections: year_result (the account(s) a closing entry carries the result on — excluded from the income statement), income_tax (the "Skatt på årets resultat" line). Seeded from the locale pack; a company arriving with its own chart remaps it here rather than in engine code.';

CREATE INDEX IF NOT EXISTS account_statement_sections_locale_section_idx
  ON public.account_statement_sections (locale, section);

ALTER TABLE public.account_statement_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read statement sections" ON public.account_statement_sections;
CREATE POLICY "Authenticated users can read statement sections"
  ON public.account_statement_sections FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins can manage statement sections" ON public.account_statement_sections;
CREATE POLICY "Admins can manage statement sections"
  ON public.account_statement_sections FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ── Sweden / BAS 2024 ───────────────────────────────────────────────────────
-- Both result accounts, not just the one LiteIT happens to use. A spot-check is
-- what let boxes 30/31/32 fall out of the first VAT seed; the whole group goes
-- in, and an account the instance's chart does not have simply never matches.
INSERT INTO public.account_statement_sections (locale, section, account_code, description) VALUES
  ('se-bas2024', 'year_result', '8990', 'Resultat'),
  ('se-bas2024', 'year_result', '8999', 'Årets resultat'),
  ('se-bas2024', 'income_tax',  '8910', 'Skatt som belastar årets resultat'),
  ('se-bas2024', 'income_tax',  '8920', 'Skatt på grund av ändrad beskattning'),
  ('se-bas2024', 'income_tax',  '8930', 'Restituerad skatt'),
  ('se-bas2024', 'income_tax',  '8940', 'Uppskjuten skatt'),
  ('se-bas2024', 'income_tax',  '8980', 'Övriga skatter')
ON CONFLICT (locale, section, account_code) DO NOTHING;

-- ── Generic / IFRS ──────────────────────────────────────────────────────────
-- year_result deliberately absent: the pack closes to Retained Earnings (3100),
-- an equity account, so no P&L line ever needs excluding.
INSERT INTO public.account_statement_sections (locale, section, account_code, description) VALUES
  ('ifrs-generic', 'income_tax', '8000', 'Income Tax Expense')
ON CONFLICT (locale, section, account_code) DO NOTHING;

-- ── The posting role ────────────────────────────────────────────────────────
-- What the year-end closing entry posts onto, and the report's fallback source
-- on an instance that has this migration's role seed but not yet the table
-- (the two arrive together here, but sync order across the fleet is not a thing
-- to rely on). Kept in step with the section map by a guardrail test.
INSERT INTO public.account_roles (locale, role, account_code, description) VALUES
  ('se-bas2024', 'year_result', '8999', 'Årets resultat — kontot bokslutsverifikationen för över resultatet på')
ON CONFLICT (locale, role) DO NOTHING;
