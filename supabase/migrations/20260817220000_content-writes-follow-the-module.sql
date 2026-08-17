-- Content writes follow the matrix (Svante-fynd #4, 2026-08-17): kb_articles
-- and blog_posts required writer/approver role literals from the pre-matrix
-- era — Svante (sales+marketing, knowledgeBase + blog modules granted) got
-- his KB edit RLS-filtered to zero rows (the read-back .single() surfaced it
-- as a json error; the loud-write fix did its job). Wiki already follows the
-- matrix and is the pattern. ADDITIVE: permissive policies OR together, so
-- the writer/approver path keeps working — the matrix path is added beside
-- it. DELETE stays admin-only everywhere, unchanged.
DROP POLICY IF EXISTS "KB articles editable by its module roles" ON public.kb_articles;
CREATE POLICY "KB articles editable by its module roles" ON public.kb_articles
  FOR UPDATE TO authenticated
  USING (can_access_module(auth.uid(), 'knowledgeBase'::text))
  WITH CHECK (can_access_module(auth.uid(), 'knowledgeBase'::text));

DROP POLICY IF EXISTS "KB articles creatable by its module roles" ON public.kb_articles;
CREATE POLICY "KB articles creatable by its module roles" ON public.kb_articles
  FOR INSERT TO authenticated
  WITH CHECK (can_access_module(auth.uid(), 'knowledgeBase'::text));

DROP POLICY IF EXISTS "KB categories manageable by its module roles" ON public.kb_categories;
CREATE POLICY "KB categories manageable by its module roles" ON public.kb_categories
  FOR ALL TO authenticated
  USING (can_access_module(auth.uid(), 'knowledgeBase'::text))
  WITH CHECK (can_access_module(auth.uid(), 'knowledgeBase'::text));

DROP POLICY IF EXISTS "Blog posts editable by its module roles" ON public.blog_posts;
CREATE POLICY "Blog posts editable by its module roles" ON public.blog_posts
  FOR UPDATE TO authenticated
  USING (can_access_module(auth.uid(), 'blog'::text))
  WITH CHECK (can_access_module(auth.uid(), 'blog'::text));

DROP POLICY IF EXISTS "Blog posts creatable by its module roles" ON public.blog_posts;
CREATE POLICY "Blog posts creatable by its module roles" ON public.blog_posts
  FOR INSERT TO authenticated
  WITH CHECK (can_access_module(auth.uid(), 'blog'::text));
