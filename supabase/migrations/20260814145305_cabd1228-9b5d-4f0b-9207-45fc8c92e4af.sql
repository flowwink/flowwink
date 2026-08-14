-- === 20260812150000_knowledge-index-bootstraps-itself.sql ===
DO $bootstrap$
DECLARE
  v_template text;
  v_command  text;
  v_url      text;
  v_headers  text;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'pg_cron not installed — skipping knowledge-indexer bootstrap.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'knowledge-indexer') THEN
    RAISE NOTICE 'knowledge-indexer cron already registered.';
    RETURN;
  END IF;

  SELECT command INTO v_template
    FROM cron.job
   WHERE command LIKE '%/functions/v1/%'
     AND command LIKE '%net.http_post%'
   ORDER BY (jobname = 'flowpilot-heartbeat') DESC,
            (jobname = 'automation-dispatcher-every-minute') DESC,
            jobname
   LIMIT 1;

  IF v_template IS NULL THEN
    RAISE NOTICE 'No HTTP cron job to derive this instance URL from — knowledge-indexer will self-register on its first run.';
    RETURN;
  END IF;

  v_url := substring(v_template from 'url\s*:=\s*''([^'']+)''');
  v_headers := substring(v_template from 'headers\s*:=\s*''([^'']+)''');

  IF v_url IS NULL OR v_headers IS NULL THEN
    RAISE NOTICE 'Could not parse url/headers from the template job — knowledge-indexer will self-register on its first run.';
    RETURN;
  END IF;

  v_url := regexp_replace(v_url, '/functions/v1/.*$', '/functions/v1/knowledge-indexer');

  v_command := format(
    'SELECT net.http_post(url := %L, headers := %L::jsonb, body := ''{"source":"cron"}''::jsonb) AS request_id;',
    v_url,
    v_headers
  );

  PERFORM cron.schedule('knowledge-indexer', '*/5 * * * *', v_command);
  RAISE NOTICE 'knowledge-indexer cron registered (every 5 minutes).';
END $bootstrap$;

INSERT INTO public.knowledge_index_queue (source_table, entity_id, op)
SELECT 'pages', id::text, 'upsert' FROM public.pages
ON CONFLICT (source_table, entity_id) DO NOTHING;
INSERT INTO public.knowledge_index_queue (source_table, entity_id, op)
SELECT 'kb_articles', id::text, 'upsert' FROM public.kb_articles
ON CONFLICT (source_table, entity_id) DO NOTHING;
INSERT INTO public.knowledge_index_queue (source_table, entity_id, op)
SELECT 'wiki_pages', slug, 'upsert' FROM public.wiki_pages
ON CONFLICT (source_table, entity_id) DO NOTHING;

DO $seed$
DECLARE v_queued int;
BEGIN
  SELECT count(*) INTO v_queued FROM public.knowledge_index_queue;
  RAISE NOTICE 'Knowledge index queue holds % item(s) for the next sweep.', v_queued;
END $seed$;

-- === 20260812160000_vendor-docs-leave-the-public-tier.sql ===
DO $vendor_docs$
DECLARE
  v_moved int;
BEGIN
  IF to_regclass('public.knowledge_chunks') IS NULL THEN
    RAISE NOTICE 'knowledge_chunks not present — nothing to reclassify.';
    RETURN;
  END IF;

  UPDATE public.knowledge_chunks
     SET visibility = 'internal'
   WHERE source_table = 'docs_pages'
     AND visibility <> 'internal';
  GET DIAGNOSTICS v_moved = ROW_COUNT;

  IF v_moved > 0 THEN
    RAISE NOTICE 'Vendor docs left the public tier: % chunk(s) reclassified to internal.', v_moved;
  ELSE
    RAISE NOTICE 'Vendor docs already internal (or none indexed).';
  END IF;
END $vendor_docs$;

-- === 20260812170000_extraction-can-be-in-flight.sql ===
ALTER TABLE public.documents
  DROP CONSTRAINT IF EXISTS documents_extraction_status_check;

ALTER TABLE public.documents
  ADD CONSTRAINT documents_extraction_status_check
  CHECK (extraction_status = ANY (ARRAY[
    'pending'::text,
    'processing'::text,
    'success'::text,
    'failed'::text,
    'unsupported'::text,
    'not_applicable'::text
  ]));

-- === 20260812180000_leads-score-on-its-own-instance.sql ===
CREATE OR REPLACE FUNCTION public.trigger_score_visitor_intent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_template text;
  v_url      text;
  v_headers  jsonb;
BEGIN
  IF NEW.email IS NULL AND NEW.phone IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF (OLD.email IS NOT DISTINCT FROM NEW.email)
       AND (OLD.phone IS NOT DISTINCT FROM NEW.phone) THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT command INTO v_template FROM cron.job WHERE jobname = 'knowledge-indexer';
  IF v_template IS NULL THEN
    RETURN NEW;
  END IF;

  v_url := substring(v_template from 'https://[^'']+/functions/v1/')
           || 'score-visitor-intent';
  v_headers := substring(v_template from 'headers := ''(\{[^'']+\})''')::jsonb;
  IF v_url IS NULL OR v_headers IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := v_headers,
    body    := jsonb_build_object('lead_id', NEW.id)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

-- === 20260813090000_the-demo-cycle-asks-what-can-be-seeded.sql ===
CREATE OR REPLACE FUNCTION public.demo_seedable_modules()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
  SELECT coalesce(array_agg(DISTINCT m[1] ORDER BY m[1]), ARRAY[]::text[])
    FROM pg_proc p
    CROSS JOIN LATERAL regexp_matches(pg_get_functiondef(p.oid), 'WHEN ''([a-z_]+)''', 'g') AS m
   WHERE p.proname = 'seed_module_demo'
     AND p.pronamespace = 'public'::regnamespace;
$$;

COMMENT ON FUNCTION public.demo_seedable_modules() IS
  'Modules seed_module_demo can stage demo data for, read from its own CASE branches. Used by demo-cycle so the nightly run covers every seeder that exists, not a snapshot of the ones that existed when the job was written.';

REVOKE ALL ON FUNCTION public.demo_seedable_modules() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_seedable_modules() TO service_role, authenticated;