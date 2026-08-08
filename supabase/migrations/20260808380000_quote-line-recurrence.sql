-- Step 2 of the recurring-value model: a quote carries a default binding term.
--
-- A quote's line items live in the JSONB `quotes.line_items` array (the
-- normalized `quote_items` table is unused — 0 rows, superseded), so per-line
-- recurrence + term ride in the InvoiceLineItem shape at the application layer,
-- not as table columns. The one real column the DB needs is the quote-level
-- default term — "this offer is for 3 years" set in one place, from which each
-- recurring line's TCV is derived. See docs/architecture/recurring-value-model.md.
--
-- Additive and nullable: a one-time quote leaves it NULL and reads as today.

ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS default_term_months integer;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'quotes_default_term_months_chk') THEN
    ALTER TABLE public.quotes
      ADD CONSTRAINT quotes_default_term_months_chk
      CHECK (default_term_months IS NULL OR default_term_months > 0);
  END IF;
END $$;
