-- Seed role_module_access_defaults — the data that made role views work
-- everywhere except on a fresh install.
--
-- Found on optic, the first from-scratch ERP install: an admin previewing the
-- Sales view saw only Dashboard, FlowPilot and Automations. Every module-gated
-- nav item was hidden, because AdminSidebar intersects the nav with
-- role_module_access — and both that table and its defaults were EMPTY. The
-- baseline ships the DDL and the reset RPCs, but no migration ever inserted the
-- data. It lived only in the hosted databases, populated out-of-band — the same
-- class as the auth trigger the demo reinstall surfaced: invisible on every
-- long-lived instance, guaranteed missing on every new one.
--
-- Rows below are dev's live defaults (the behaviour everyone knows), with two
-- ids modernised in transit: `resume` → `consultants` (module renamed 2026-07-12,
-- full-wire) and `orders` → `ecommerce` (merged in useModules). Dev's own data
-- still carries the stale names; copying them verbatim would seed rows no nav
-- item can match. On instances that already have rows, ON CONFLICT DO NOTHING
-- makes this a no-op apart from adding the modernised ids alongside.
--
-- The live table is only filled where it is EMPTY. reset_all_role_module_access
-- exists for operators and deletes before copying; a migration must not stomp an
-- operator's customised role grants just because it re-ran.

INSERT INTO public.role_module_access_defaults (role, module_id)
SELECT r.role::public.app_role, m.module_id
FROM (VALUES
  ('accounting', ARRAY['accounting','approvals','documents','expenses','invoicing','purchasing','quotes','reconciliation','subscriptions','timesheets']),
  ('hr',         ARRAY['calendar','contracts','documents','handbook','hr','recruitment']),
  ('marketing',  ARRAY['companyInsights','forms','newsletter','webinars']),
  ('projects',   ARRAY['calendar','documents','projects']),
  ('purchasing', ARRAY['purchasing']),
  ('sales',      ARRAY['bookings','calendar','companies','companyInsights','deals','leads','ecommerce','quotes','consultants','salesIntelligence']),
  ('support',    ARRAY['calendar','liveSupport','sla','tickets','workspaceChat']),
  ('warehouse',  ARRAY['ecommerce','inventory'])
) AS r(role, modules)
CROSS JOIN LATERAL unnest(r.modules) AS m(module_id)
ON CONFLICT DO NOTHING;

-- Fill the live table only when nothing is there: a fresh install gets working
-- role views immediately, an operated instance keeps its grants untouched.
INSERT INTO public.role_module_access (role, module_id)
SELECT role, module_id FROM public.role_module_access_defaults
WHERE NOT EXISTS (SELECT 1 FROM public.role_module_access)
ON CONFLICT DO NOTHING;
