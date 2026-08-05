DO $$
BEGIN
  UPDATE public.pipeline_stages
     SET name = 'Opportunity', key = 'opportunity', sort_order = 20
   WHERE entity_type = 'lead'
     AND key = 'qualified'
     AND NOT EXISTS (
       SELECT 1 FROM public.pipeline_stages
        WHERE entity_type = 'lead' AND key = 'opportunity'
     );

  INSERT INTO public.pipeline_stages (entity_type, key, name, sort_order, probability, is_won, is_lost, fold)
  SELECT * FROM (VALUES
    ('lead','lead','New',10,10::numeric,false,false,false),
    ('lead','opportunity','Opportunity',20,50::numeric,false,false,false),
    ('lead','customer','Customer',30,100::numeric,true,false,false),
    ('lead','lost','Lost',40,0::numeric,false,true,true)
  ) AS v(entity_type, key, name, sort_order, probability, is_won, is_lost, fold)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pipeline_stages p
     WHERE p.entity_type = v.entity_type AND p.key = v.key
  );
END $$;

UPDATE public.leads l
   SET stage_id = p.id
  FROM public.pipeline_stages p
 WHERE p.entity_type = 'lead'
   AND p.key = l.status::text
   AND l.stage_id IS NULL;