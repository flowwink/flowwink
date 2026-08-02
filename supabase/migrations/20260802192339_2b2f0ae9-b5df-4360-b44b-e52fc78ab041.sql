DO $$
DECLARE r jsonb;
BEGIN
  r := progress_work_order('25553074-90b2-466d-83e0-425c81022b3f','start',null);
  RAISE NOTICE 'start: %', r;
  r := progress_work_order('25553074-90b2-466d-83e0-425c81022b3f','done',52);
  RAISE NOTICE 'done: %', r;
END $$;