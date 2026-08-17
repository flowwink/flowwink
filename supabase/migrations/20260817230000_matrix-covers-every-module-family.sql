-- Rollsvepet #102, strukturhål B: matriskartan täckte aldrig alla modulfamiljer.
-- En roll kunde få nav + sida för t.ex. payroll eller voice men nekas varje
-- skrivning, eftersom varken defaults-kartan eller live-matrisen hade rader för
-- modulen. Detta kompletterar BÅDA, additivt:
--   * role_module_access_defaults — styr nyinstaller (seedas av setup-database)
--   * role_module_access          — live-matrisen; ON CONFLICT DO NOTHING så
--     operatörens egna beviljanden/återkallanden aldrig skrivs över.
--
-- MEDVETET INTE seedade (beslut 2026-08-17, ordförande Claude):
--   * pos, federation — nisch resp. plattform-till-plattform; operatören
--     beviljar explicit. Frånvaro i matrisen = admin-only, vilket är rätt default.
--   * developer, templates, composio, browserControl m.fl. plattformsverktyg.
-- Blog + chat fanns live på optic (manuellt beviljade) men aldrig i defaults —
-- de lyfts in så nyinstaller föds med samma löfte.

DO $$
DECLARE
  pair record;
BEGIN
  FOR pair IN
    SELECT * FROM (VALUES
      -- HR-familjen
      ('hr',         'payroll'),
      -- Ekonomifamiljen
      ('accounting', 'fixedAssets'),
      ('accounting', 'multiCurrency'),
      -- Supportfamiljen
      ('support',    'voice'),
      ('support',    'surveys'),
      ('support',    'fieldService'),
      ('support',    'returns'),
      ('support',    'chat'),
      -- Lager/logistik
      ('warehouse',  'shipping'),
      ('warehouse',  'returns'),
      ('warehouse',  'manufacturing'),
      -- Marknad
      ('marketing',  'surveys'),
      ('marketing',  'paidGrowth'),
      ('marketing',  'blog'),
      ('marketing',  'chat'),
      -- Sälj
      ('sales',      'pricelists')
    ) AS t(role_name, module_id)
  LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    VALUES (pair.role_name::public.app_role, pair.module_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.role_module_access (role, module_id)
    VALUES (pair.role_name::public.app_role, pair.module_id)
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
