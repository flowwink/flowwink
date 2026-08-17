-- Svante-fynd 2026-08-17 (kväll #2): forms-modulen i matrisen gav läsning av
-- inskick men radering krävde admin — pre-matris-kvarleva. Att rensa skräp
-- och GDPR-radera svar är modulägarens vardag (jfr expense-attest), till
-- skillnad från att radera PUBLICERAT innehåll där admin-spärren är medveten.
DO $$
BEGIN
  IF to_regclass('public.form_submissions') IS NOT NULL THEN
    DROP POLICY IF EXISTS "forms module deletes form_submissions" ON public.form_submissions;
    CREATE POLICY "forms module deletes form_submissions" ON public.form_submissions
      FOR DELETE USING (public.can_access_module(auth.uid(), 'forms'));
  END IF;
END $$;
