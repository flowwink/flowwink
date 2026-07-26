-- Restore writes to lead_activities — "Log activity" has been dead since 2026-06-16.
--
-- Migration 20260616190226 dropped eight policies under the heading
--   "Drop anon-write policies on internal/system tables (service_role bypasses RLS)"
-- and the reasoning held for seven of them: those tables are written by edge
-- functions running as service_role, which bypasses RLS, so a permissive
-- WITH CHECK (true) was pure attack surface.
--
-- lead_activities was the exception. It is ALSO written by the admin UI as a
-- logged-in user (useLogActivity → Note / Call / Email / Meeting on the contact
-- page), and unlike quotes and consultant_profiles — which survived because they
-- carry an "Admins can manage" ALL policy — it had nothing to fall back on. It
-- was left with a single SELECT policy, so nobody but service_role could write.
-- Every Log-activity button on every instance has failed for six weeks.
--
-- The fix keeps the hardening's intent rather than reinstating the old blanket
-- policy: staff may write, anon may not. is_staff() is the predicate introduced
-- in 20260726180000 ("has at least one non-customer role"), so customer-portal
-- users are excluded here as they are on the other internal tables.
--
-- Forward-dated because Lovable's migrate runner skips anything below its ledger
-- head, and this has to reach the managed dev instance.

-- The existence check matches on the SIGNATURE, not the name. is_staff takes a
-- uuid; a name-only check would pass and then the policy body would fail on the
-- wrong arity — the same class of miss as checking pg_proc by name and assuming
-- the body is current.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_staff' AND n.nspname = 'public'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid'
  ) THEN
    DROP POLICY IF EXISTS "Staff can log lead activities" ON public.lead_activities;
    CREATE POLICY "Staff can log lead activities"
      ON public.lead_activities FOR INSERT
      TO authenticated
      WITH CHECK (public.is_staff(auth.uid()));
  ELSE
    -- Instance predates the staff predicate: fall back to the roles it does have,
    -- so the button works there too rather than failing differently.
    DROP POLICY IF EXISTS "Staff can log lead activities" ON public.lead_activities;
    CREATE POLICY "Staff can log lead activities"
      ON public.lead_activities FOR INSERT
      TO authenticated
      WITH CHECK (
        public.has_role(auth.uid(), 'admin'::public.app_role)
        OR public.has_role(auth.uid(), 'approver'::public.app_role)
      );
  END IF;
END $$;

COMMENT ON TABLE public.lead_activities IS
  'Timeline entries for a lead/contact. Written by staff via the admin UI '
  '(useLogActivity) and by agents via service_role. INSERT is gated on is_staff() '
  'so customer-portal users cannot write; see 20260726230000 for why the earlier '
  'blanket policy could not simply be dropped.';
