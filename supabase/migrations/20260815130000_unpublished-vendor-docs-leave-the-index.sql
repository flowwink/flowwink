-- Unpublished vendor docs leave the knowledge index (#95 companion).
--
-- The /docs chat now grounds through retrieveVendorDocs — service eyes with
-- the source pinned to docs_pages (the one named exception to caller's-eyes
-- retrieval; see _shared/retrieval/vendor-docs.ts). Service eyes bypass RLS,
-- so the index itself must not hold chunks for docs pages an admin has
-- unpublished. The indexer now gates on is_published at extract time; this
-- migration removes what was indexed before that gate existed.
--
-- (docs-sync never writes is_published, so the column default TRUE makes this
-- a no-op on most instances — it exists for the admin-unpublished class.)
--
-- Idempotent: re-running deletes nothing new.

DO $unpublished_docs$
DECLARE
  v_removed int;
BEGIN
  IF to_regclass('public.knowledge_chunks') IS NULL
     OR to_regclass('public.docs_pages') IS NULL THEN
    RAISE NOTICE 'knowledge_chunks or docs_pages not present — nothing to clean.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'docs_pages'
      AND column_name = 'is_published'
  ) THEN
    RAISE NOTICE 'docs_pages.is_published not present — nothing to clean.';
    RETURN;
  END IF;

  DELETE FROM public.knowledge_chunks kc
   WHERE kc.source_table = 'docs_pages'
     AND EXISTS (
       SELECT 1 FROM public.docs_pages dp
        WHERE dp.id::text = kc.entity_id
          AND dp.is_published = false
     );
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  IF v_removed > 0 THEN
    RAISE NOTICE 'Unpublished vendor docs left the index: % chunk(s) removed.', v_removed;
  ELSE
    RAISE NOTICE 'No chunks of unpublished vendor docs found.';
  END IF;
END $unpublished_docs$;
