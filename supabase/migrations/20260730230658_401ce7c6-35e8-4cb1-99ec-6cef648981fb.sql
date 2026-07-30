DELETE FROM public.ticket_comments c
USING public.tickets t
WHERE c.ticket_id = t.id
  AND t.source = 'email'
  AND t.status = 'new'
  AND t.created_at >= TIMESTAMPTZ '2026-07-26 00:00:00+00'
  AND t.assigned_to IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.ticket_comments c2
    WHERE c2.ticket_id = t.id AND c2.author_type <> 'customer'
  );

DELETE FROM public.tickets t
WHERE t.source = 'email'
  AND t.status = 'new'
  AND t.created_at >= TIMESTAMPTZ '2026-07-26 00:00:00+00'
  AND t.assigned_to IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.ticket_comments c2
    WHERE c2.ticket_id = t.id AND c2.author_type <> 'customer'
  );