ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferences jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.flowtable_bases ALTER COLUMN owner_id DROP NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'flowtable_bases_owner_id_fkey'
      AND conrelid = 'public.flowtable_bases'::regclass
      AND confdeltype = 'c'
  ) THEN
    ALTER TABLE public.flowtable_bases DROP CONSTRAINT flowtable_bases_owner_id_fkey;
    ALTER TABLE public.flowtable_bases
      ADD CONSTRAINT flowtable_bases_owner_id_fkey
      FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DROP POLICY IF EXISTS "flowtable_bases owner update" ON public.flowtable_bases;
CREATE POLICY "flowtable_bases owner update"
  ON public.flowtable_bases FOR UPDATE
  USING (owner_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "flowtable_bases owner delete" ON public.flowtable_bases;
CREATE POLICY "flowtable_bases owner delete"
  ON public.flowtable_bases FOR DELETE
  USING (owner_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE OR REPLACE FUNCTION public.detach_user_references(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  r record;
  v_count bigint;
  v_out jsonb := '{}'::jsonb;
  v_blockers text := '';
BEGIN
  IF NOT (auth.role() = 'service_role'
          OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN
    RAISE EXCEPTION 'detach_user_references: admin or service role required';
  END IF;

  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname AS col, a.attnotnull AS not_null
    FROM pg_constraint c
    JOIN unnest(c.conkey) k(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    JOIN pg_class cl ON cl.oid = c.conrelid
    WHERE c.contype = 'f'
      AND c.confdeltype = 'a'
      AND c.confrelid IN ('auth.users'::regclass, 'public.profiles'::regclass)
      AND cl.relnamespace = 'public'::regnamespace
  LOOP
    IF r.not_null THEN
      EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col)
        USING p_user_id INTO v_count;
      IF v_count > 0 THEN
        v_blockers := v_blockers || format('%s.%s (%s rows) ', r.tbl, r.col, v_count);
      END IF;
      CONTINUE;
    END IF;

    EXECUTE format('UPDATE %s SET %I = NULL WHERE %I = $1', r.tbl, r.col, r.col)
      USING p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count > 0 THEN
      v_out := v_out || jsonb_build_object(r.tbl || '.' || r.col, v_count);
    END IF;
  END LOOP;

  IF v_blockers <> '' THEN
    RAISE EXCEPTION 'User has NOT NULL references that cannot be detached: %. These columns need a schema decision (nullable, or reassignment) before this user can be deleted.', v_blockers;
  END IF;

  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.detach_user_references(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detach_user_references(uuid) TO authenticated, service_role;