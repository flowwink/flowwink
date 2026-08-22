-- Repair four SE-BAS 2024 accounts referenced by posted journal_entry_lines but
-- absent from chart_of_accounts, causing balance_sheet (which joins on
-- chart_of_accounts.account_type) to silently drop those lines and imbalance.
--
-- COUNTRY GUARD (2026-08-22, se 20260822234500): this file used to plant four
-- Swedish rows on EVERY install in the world, including one that had never
-- picked a market. That is the opposite of the file's own purpose — it was
-- written to repair an instance whose BOOKS already named these accounts.
-- The repair is now conditional on that being true: either the instance has
-- explicitly activated se-bas2024, or its journal already posts to the code.
-- A virgin install matches neither and gets nothing, which is the state
-- useTenantLocalePack and account_for are built on (empty-until-chosen).
--
-- Editing an applied migration is safe here because the end state of every
-- instance that already ran it is unchanged: the rows it planted are still
-- there, and on those instances the guard is true anyway. What changes is only
-- what a FRESH chain produces. The ON CONFLICT DO UPDATE became
-- WHERE NOT EXISTS for the same reason 20260726090000 did (the unique key is
-- (locale, account_code) since 2026-08-09, so naming a constraint from this
-- file's era is 42P10 on replay); classification of already-planted rows is
-- long since owned by 20260809160000_bas2024-chart-names-from-standard.

INSERT INTO public.chart_of_accounts
  (account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
SELECT v.*
FROM (VALUES
  ('1210', 'Maskiner och andra tekniska anläggningar', 'asset',     'tillgångar',   'debit',  true, 'se-bas2024'),
  ('2090', 'Balanserad vinst eller förlust',           'equity',    'eget kapital', 'credit', true, 'se-bas2024'),
  ('2641', 'Debiterad ingående moms',                  'asset',     'tillgångar',   'debit',  true, 'se-bas2024'),
  ('7970', 'Förlust vid avyttring av immateriella och materiella anläggningstillgångar',
                                                       'expense',   'kostnader',    'debit',  true, 'se-bas2024')
) AS v(account_code, account_name, account_type, account_category, normal_balance, is_active, locale)
WHERE NOT EXISTS (
  SELECT 1 FROM public.chart_of_accounts c
   WHERE c.account_code = v.account_code AND c.locale = v.locale
)
AND (
  -- The instance has chosen this market …
  EXISTS (
    SELECT 1 FROM public.site_settings s
     WHERE s.key = 'accounting_locale'
       AND COALESCE(s.value ->> 'id', NULLIF(s.value #>> '{}', '')) = 'se-bas2024'
  )
  -- … or its books already name the account, which is the case this file
  -- was written to repair.
  OR EXISTS (
    SELECT 1 FROM public.journal_entry_lines l WHERE l.account_code = v.account_code
  )
);
