---
name: invites and access truth
description: Invites go through the operator's own email rail (generateLink + email-send), functional roles, route gating via navigationGroups, is_staff() read paths, delete-user detaches via pg_constraint
type: preference
---

# Users, access & invites

- **Never use Supabase Auth's built-in mailer.** Use
  `generateLink({type:'invite'})` (creates user + token, sends nothing) then
  `email-send` — operator's own provider, verified domain, branded shell.
  `simulated: true` must NOT be reported as "sent": say "Account created —
  email not sent" and hand over the link. Role reconciliation runs regardless.
- Invitable roles pinned to `FUNCTIONAL_ROLES` in `src/types/cms.ts` (+ admin),
  guardrail compares edge function and dialog lists.
- Customers activate at `/account/activate` with the invited email **read-only**
  — a signup form there orphans the account holding their service.
- **Hiding is not gating**: route access resolves the pathname against the same
  `navigationGroups` the sidebar renders (`src/lib/admin-route-access.ts`).
- **Read gating uses `is_staff()`**; `approver` is a legacy CMS role nobody
  holds — gating reads on it produces empty pages, the worst failure mode.
  HR-sensitive → admin+hr, finance → admin+accounting.
- **Verify RLS behaviourally** (`SET LOCAL ROLE authenticated` + JWT claims), not
  by reading policy text. Policy *names* lie in both directions (policies named
  for service_role with `roles={public}, qual=true`).
- Primary role display: admin → functional → `customer` last; `customer` must be
  removable in the roles popover.
- `delete-user` detaches via `detach_user_references()` walking `pg_constraint`
  at execution time (hardcoded column lists rot). Authorship nulled, business
  rows kept.

Docs: `docs/operators/users-access-and-invites.md`
