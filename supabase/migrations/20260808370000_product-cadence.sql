-- Step 1 of the recurring-value model: a recurring product carries its CADENCE.
--
-- products.type is already one_time|recurring — the flag exists. But
-- "recurring, 10 000" is dimensionless: per what? This adds the one atomic fact
-- the product is first to know — the billing interval — so the price can travel
-- the sales chain WITH its dimension instead of having it reinvented at the
-- contract. See docs/architecture/recurring-value-model.md.
--
-- Additive and nullable: a one_time product leaves these NULL and every rollup
-- downstream collapses to the scalar, so the product-sales flow is untouched.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS billing_interval text,
  ADD COLUMN IF NOT EXISTS default_term_months integer;

-- 'month' | 'year' — only meaningful when type='recurring'. NULL is valid
-- (one_time, or a recurring product priced per-month by convention).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'products_billing_interval_chk'
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_billing_interval_chk
      CHECK (billing_interval IS NULL OR billing_interval IN ('month', 'year'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'products_default_term_months_chk'
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_default_term_months_chk
      CHECK (default_term_months IS NULL OR default_term_months > 0);
  END IF;
END $$;

-- Backfill: an existing recurring product with no interval bills monthly — the
-- overwhelmingly common cadence and what the telco fixtures assume. One_time
-- products are left NULL.
UPDATE public.products
SET billing_interval = 'month'
WHERE type = 'recurring' AND billing_interval IS NULL;
