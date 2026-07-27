-- Backfill: link Elin's inbound reply to her lead (thread key was gmail id, outbound row was keyed by subject)
UPDATE public.outbound_communications
SET related_entity_type = 'lead',
    related_entity_id = 'debf4a00-8920-424c-ac4a-ef334dc43cd7'
WHERE id = 'e97de575-4c24-407b-8a5f-25ba184137e1'
  AND related_entity_id IS NULL;

-- Also set thread_key on the email_threads row for the gmail thread id
UPDATE public.email_threads
SET related_entity_type = 'lead',
    related_entity_id = 'debf4a00-8920-424c-ac4a-ef334dc43cd7'
WHERE thread_key = '19fa2c86caa2fe43'
  AND related_entity_id IS NULL;