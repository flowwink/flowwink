-- Sales owns the customer lifecycle — all of it.
--
-- Product decision (Magnus, 2026-08-13, after testing the matrix live on
-- autoversio): a salesperson is responsible for the whole chain
--
--   Contact → Deal → Quote → Contract → Subscription → Ticket
--
-- The defaults granted the first half (leads, deals, quotes) and stopped at
-- the signature: contracts, subscriptions and tickets were other departments'
-- modules. But the person who sold the deal is who the customer calls, and a
-- seller who cannot see the customer's contract, what they subscribe to, or
-- their open tickets is blind for exactly the conversations that renew revenue.
--
-- Same re-assertable shape as the shared-surface migrations: insert-if-absent
-- into defaults and the live matrix, so an operator who deliberately revoked
-- one of these keeps their decision.

DO $$
DECLARE
  LIFECYCLE text[] := ARRAY['contracts', 'subscriptions', 'tickets'];
  m text;
  r record;
BEGIN
  FOREACH m IN ARRAY LIFECYCLE LOOP
    INSERT INTO public.role_module_access_defaults (role, module_id)
    SELECT 'sales', m
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access_defaults x
        WHERE x.role = 'sales' AND x.module_id = m
     );

    INSERT INTO public.role_module_access (role, module_id)
    SELECT 'sales', m
     WHERE NOT EXISTS (
       SELECT 1 FROM public.role_module_access x
        WHERE x.role = 'sales' AND x.module_id = m
     );
  END LOOP;

  FOR r IN
    SELECT module_id FROM public.role_module_access
     WHERE role = 'sales' AND module_id = ANY(LIFECYCLE) ORDER BY module_id
  LOOP
    RAISE NOTICE 'sales lifecycle grant: %', r.module_id;
  END LOOP;
END $$;
