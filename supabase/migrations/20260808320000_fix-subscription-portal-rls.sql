-- The portal subscription policy read auth.users — a table `authenticated`
-- cannot select. Postgres raised "permission denied for table users" while
-- EVALUATING the policy, which fails the whole check: neither a customer nor
-- an admin could read subscriptions. The admin subscriptions page went blank
-- and the service born from a signed contract was invisible to everyone. The
-- policy looked right; the read path it opened never worked — the envelope
-- lie, in RLS.
--
-- Fix: take the caller's email from the JWT (auth.jwt() ->> 'email'), which
-- needs no table access, and keep is_staff() for staff. Same allow shape,
-- no privileged table read.
DROP POLICY IF EXISTS "Customers read own subscriptions" ON public.subscriptions;
CREATE POLICY "Customers read own subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (
    is_staff(auth.uid())
    OR lower(customer_email) = lower(auth.jwt() ->> 'email')
  );
