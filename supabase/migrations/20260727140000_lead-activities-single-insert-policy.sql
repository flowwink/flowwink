-- One INSERT policy on lead_activities, not two.
--
-- Two migrations fixed the same thing within an hour of each other, from
-- opposite ends: 20260726230000 restored writes after the 2026-06-16 hardening
-- dropped the table's only writer, and 20260727113126 added them again while
-- wiring the contact page. Policies are OR'd, so nothing broke — but the two
-- carry different role lists, and the next person to read them cannot tell which
-- one is authoritative or why they disagree. Redundant permissions are how a
-- grant nobody intended survives a later tightening.
--
-- The surviving policy takes the union of both role lists. Lovable's was the
-- more complete one: logging a call or a note is ordinary sales and editorial
-- work, not something to reserve for admins and approvers.
--
-- Still written to prefer is_staff() when it exists. That predicate belongs to
-- migration 20260726180000, which has NOT landed on any instance we can check
-- (verified 2026-07-26 on liteit and dev — the function is absent from pg_proc
-- on both). The role list is therefore what actually runs today; is_staff() takes
-- over by itself once that migration is applied, with no further change here.
--
-- The signature check matters: is_staff takes a uuid, so a name-only existence
-- test passes and then the policy body fails on arity.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Staff can log lead activities" ON public.lead_activities;
  DROP POLICY IF EXISTS "Staff can insert lead activities" ON public.lead_activities;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_staff' AND n.nspname = 'public'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid'
  ) THEN
    CREATE POLICY "Staff can log lead activities"
      ON public.lead_activities FOR INSERT
      TO authenticated
      WITH CHECK (public.is_staff(auth.uid()));
  ELSE
    CREATE POLICY "Staff can log lead activities"
      ON public.lead_activities FOR INSERT
      TO authenticated
      WITH CHECK (
        public.has_role(auth.uid(), 'admin'::public.app_role)
        OR public.has_role(auth.uid(), 'approver'::public.app_role)
        OR public.has_role(auth.uid(), 'sales'::public.app_role)
        OR public.has_role(auth.uid(), 'writer'::public.app_role)
      );
  END IF;
END $$;

-- UPDATE and DELETE from 20260727113126 are left alone: they are new capability
-- for the contact page's edit and remove actions, not duplicates of anything.
