-- === 20260812130000_fresh-install-finalizer.sql (policies + cron) ===
DO $fin$
DECLARE
  attempt int := 0;
BEGIN
  LOOP
    attempt := attempt + 1;
    BEGIN
      DROP POLICY IF EXISTS "Authenticated users can view documents" ON storage.objects;
      DROP POLICY IF EXISTS "Authenticated users can update documents" ON storage.objects;

      DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;
      CREATE POLICY "Admins can delete documents" ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'documents'::text) AND has_role(auth.uid(), 'admin'::app_role)));
      DROP POLICY IF EXISTS "Anyone can view cms images" ON storage.objects;
      CREATE POLICY "Anyone can view cms images" ON storage.objects FOR SELECT TO public USING ((bucket_id = 'cms-images'::text));
      DROP POLICY IF EXISTS "Authenticated users can delete images" ON storage.objects;
      CREATE POLICY "Authenticated users can delete images" ON storage.objects FOR DELETE TO authenticated USING ((bucket_id = 'cms-images'::text));
      DROP POLICY IF EXISTS "Authenticated users can update images" ON storage.objects;
      CREATE POLICY "Authenticated users can update images" ON storage.objects FOR UPDATE TO authenticated USING ((bucket_id = 'cms-images'::text));
      DROP POLICY IF EXISTS "Authenticated users can upload documents" ON storage.objects;
      CREATE POLICY "Authenticated users can upload documents" ON storage.objects FOR INSERT TO authenticated WITH CHECK ((bucket_id = 'documents'::text));
      DROP POLICY IF EXISTS "Authenticated users can upload images" ON storage.objects;
      CREATE POLICY "Authenticated users can upload images" ON storage.objects FOR INSERT TO authenticated WITH CHECK ((bucket_id = 'cms-images'::text));
      DROP POLICY IF EXISTS "Document files follow their document's visibility" ON storage.objects;
      CREATE POLICY "Document files follow their document's visibility" ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'documents'::text) AND (has_role(auth.uid(), 'admin'::app_role) OR ((storage.foldername(name))[1] = (auth.uid())::text) OR (EXISTS ( SELECT 1
         FROM documents d
        WHERE (d.file_url = objects.name))))));
      DROP POLICY IF EXISTS "Uploaders and admins can overwrite document files" ON storage.objects;
      CREATE POLICY "Uploaders and admins can overwrite document files" ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'documents'::text) AND (has_role(auth.uid(), 'admin'::app_role) OR ((storage.foldername(name))[1] = (auth.uid())::text) OR (EXISTS ( SELECT 1
         FROM documents d
        WHERE ((d.file_url = objects.name) AND (d.uploaded_by = auth.uid())))))));
      DROP POLICY IF EXISTS "cowork own delete" ON storage.objects;
      CREATE POLICY "cowork own delete" ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'cowork-uploads'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
      DROP POLICY IF EXISTS "cowork own read" ON storage.objects;
      CREATE POLICY "cowork own read" ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'cowork-uploads'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
      DROP POLICY IF EXISTS "cowork own upload" ON storage.objects;
      CREATE POLICY "cowork own upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'cowork-uploads'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
      DROP POLICY IF EXISTS "form-uploads admin delete" ON storage.objects;
      CREATE POLICY "form-uploads admin delete" ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'form-uploads'::text) AND has_role(auth.uid(), 'admin'::app_role)));
      DROP POLICY IF EXISTS "form-uploads admin read" ON storage.objects;
      CREATE POLICY "form-uploads admin read" ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'form-uploads'::text) AND has_role(auth.uid(), 'admin'::app_role)));
      DROP POLICY IF EXISTS "form-uploads insert" ON storage.objects;
      CREATE POLICY "form-uploads insert" ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK ((bucket_id = 'form-uploads'::text));
      DROP POLICY IF EXISTS "river-media authed upload" ON storage.objects;
      CREATE POLICY "river-media authed upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK ((bucket_id = 'river-media'::text));
      DROP POLICY IF EXISTS "river-media owner delete" ON storage.objects;
      CREATE POLICY "river-media owner delete" ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'river-media'::text) AND (owner = auth.uid())));
      DROP POLICY IF EXISTS "river-media public read" ON storage.objects;
      CREATE POLICY "river-media public read" ON storage.objects FOR SELECT TO public USING ((bucket_id = 'river-media'::text));
      EXIT;
    EXCEPTION WHEN deadlock_detected THEN
      IF attempt >= 5 THEN RAISE; END IF;
      RAISE NOTICE 'Storage bootstrap hit a deadlock (attempt %); retrying…', attempt;
      PERFORM pg_sleep(attempt * 2);
    END;
  END LOOP;

  IF to_regclass('cron.job') IS NOT NULL THEN
    DECLARE r record; BEGIN
      FOR r IN SELECT jobid FROM cron.job LOOP
        PERFORM cron.alter_job(r.jobid, active => true);
      END LOOP;
    END;
    RAISE NOTICE 'Fresh-install finalizer: % cron job(s) activated.', (SELECT count(*) FROM cron.job);
  END IF;
  RAISE NOTICE 'Fresh-install finalizer complete: % bucket(s), % storage policies.',
    (SELECT count(*) FROM storage.buckets),
    (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects');
END $fin$;