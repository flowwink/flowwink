-- "Service role" policies that actually admitted everyone.
--
-- The service key BYPASSES RLS entirely — a policy is never needed for it.
-- Yet four tables carried policies NAMED for the service role with
-- roles={public} or {authenticated} and qual/check=true, which means the
-- policy admitted every caller EXCEPT the one it was named after:
--
--   federation_peer_missions  INSERT/UPDATE/SELECT true for public — anyone,
--                             anonymous included, could create or rewrite the
--                             missions federation agents read and follow.
--                             Prompt injection by database row.
--   agent_audit_trail         INSERT check=true for authenticated — any
--                             logged-in user could forge audit entries.
--   beta_test_*               anon+authenticated INSERT/UPDATE/DELETE true —
--                             QA findings writable and deletable by anyone.
--   installed_template        public INSERT true.
--
-- Found by reading QUALS, not policy names: the same sweep first flagged
-- purchase_orders as wide open because its policy is NAMED "Authenticated
-- users full access" — its qual is is_staff(). Names lie in both directions.
--
-- Every legitimate writer of these tables (edge functions, the MCP gateway,
-- crons) runs with the service key, so dropping the policies removes no
-- capability — it removes an accident.

-- federation_peer_missions: service bypasses; admins manage via UI.
DROP POLICY IF EXISTS "Service role can manage missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Service role can update missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Service role can read missions" ON public.federation_peer_missions;
DROP POLICY IF EXISTS "Admins manage federation_peer_missions" ON public.federation_peer_missions;
CREATE POLICY "Admins manage federation_peer_missions" ON public.federation_peer_missions
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
-- "Peers can read own mission" stays as-is.

-- agent_audit_trail: only the service key writes; the deny-policies for
-- UPDATE/DELETE already exist and stay.
DROP POLICY IF EXISTS "Service inserts audit trail" ON public.agent_audit_trail;

-- beta_test_*: written by the MCP gateway (service key). Admins may curate.
DROP POLICY IF EXISTS "Allow anon insert on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated update on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Allow authenticated delete on beta_test_findings" ON public.beta_test_findings;
DROP POLICY IF EXISTS "Admins manage beta_test_findings" ON public.beta_test_findings;
CREATE POLICY "Admins manage beta_test_findings" ON public.beta_test_findings
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Allow anon insert on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow anon update on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Allow authenticated update on beta_test_sessions" ON public.beta_test_sessions;
DROP POLICY IF EXISTS "Admins manage beta_test_sessions" ON public.beta_test_sessions;
CREATE POLICY "Admins manage beta_test_sessions" ON public.beta_test_sessions
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Allow anon insert on beta_test_exchanges" ON public.beta_test_exchanges;
DROP POLICY IF EXISTS "Allow authenticated insert on beta_test_exchanges" ON public.beta_test_exchanges;
DROP POLICY IF EXISTS "Admins manage beta_test_exchanges" ON public.beta_test_exchanges;
CREATE POLICY "Admins manage beta_test_exchanges" ON public.beta_test_exchanges
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- installed_template: written by setup (service key); admin policy exists.
DROP POLICY IF EXISTS "System can insert installed_template" ON public.installed_template;
