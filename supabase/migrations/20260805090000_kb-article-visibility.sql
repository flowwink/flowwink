-- Internal knowledge belongs in the KB, not in a different product.
--
-- Until now a KB article was public or it did not exist: the chunk indexer
-- hardcoded visibility 'public' for every kb_articles row and 'internal' for
-- every wiki_pages row, so audience was a property of the TABLE. The only way
-- to hide internal Q&A was to move it to the wiki — trading away the question/
-- answer shape, the categories, and the helpful/needs_improvement loop that
-- make the KB worth using, purely to control who can read it. Form and access
-- became the same axis, which is the same mistake as using modules as an ACL.
--
-- Found on optic (2026-08-04): five sales-enablement articles written in the
-- seller's voice ("how do we handle the objection that…", "have the answers
-- before the meeting") were published on the public help centre and fed to the
-- site chat, so a prospect could have been served the playbook aimed at them.
--
-- The hard part was already built. knowledge_chunks.visibility exists, RLS
-- enforces it, and retrieval runs with the caller's own client — anonymous
-- visitors can only ground answers in 'public' chunks. What was missing is a
-- source that can EXPRESS the distinction. This adds it.
--
-- Wiki is deliberately untouched: its visibility column already defaults to
-- 'internal' and its SELECT policy already requires a logged-in user, so the
-- indexer's hardcoded 'internal' matches reality there.

-- ─── 1. The column ──────────────────────────────────────────────────────────
ALTER TABLE public.kb_articles
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'kb_articles_visibility_check'
  ) THEN
    ALTER TABLE public.kb_articles
      ADD CONSTRAINT kb_articles_visibility_check
      CHECK (visibility IN ('public', 'internal'));
  END IF;
END $$;

COMMENT ON COLUMN public.kb_articles.visibility IS
  'public = anyone may read it and the site chat may ground answers in it. '
  'internal = staff only; the support team and staff-facing agents see it, '
  'visitors never do. Default public so existing articles keep their audience.';

CREATE INDEX IF NOT EXISTS kb_articles_visibility_published_idx
  ON public.kb_articles (visibility, is_published);

-- ─── 2. is_staff, defined here too ──────────────────────────────────────────
-- 20260726180000 introduced it, but that migration predates some instances'
-- ledger head and was skipped there (the backdating trap). This migration must
-- not assume it exists — an internal tier whose predicate is missing would fail
-- closed at best and error at worst. CREATE OR REPLACE is a no-op where it
-- already landed.
CREATE OR REPLACE FUNCTION public.is_staff(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role <> 'customer'
  );
$$;

-- ─── 3. Read policies ───────────────────────────────────────────────────────
-- The client-side filters added alongside this migration are for correct counts
-- and tidy UI. THIS is the gate.
DROP POLICY IF EXISTS "Public can view published articles" ON public.kb_articles;
DROP POLICY IF EXISTS "Public can view published public articles" ON public.kb_articles;
CREATE POLICY "Public can view published public articles"
  ON public.kb_articles FOR SELECT
  USING (is_published = true AND visibility = 'public');

-- Replaces "Authenticated can view all articles", which let ANY logged-in user
-- read every row. On a single-admin instance that is inert; on one with a
-- customer portal it meant customers could read unpublished drafts — and would
-- now mean they could read the internal tier. Staff keep exactly what they had
-- (everything, drafts included); customer accounts drop to the public surface.
DROP POLICY IF EXISTS "Authenticated can view all articles" ON public.kb_articles;
DROP POLICY IF EXISTS "Staff view all articles, others the public ones" ON public.kb_articles;
CREATE POLICY "Staff view all articles, others the public ones"
  ON public.kb_articles FOR SELECT
  TO authenticated
  USING (
    public.is_staff(auth.uid())
    OR (is_published = true AND visibility = 'public')
  );
