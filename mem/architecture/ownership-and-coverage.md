---
name: ownership is a lens never RLS
description: CRM ownership model — one column map, inheritance outranks creator, Mine/All lens in profiles.preferences, date-predicate coverage; ownership must never appear in RLS
type: constraint
---

# Ownership & coverage

**Ownership columns must NEVER appear in RLS policies.** Access is the vertical
axis (which modules a functional role may open); rows are never hidden on the
horizontal axis. Odoo's record rules are the anti-pattern — that is where two
salespeople call the same customer twice. Guardrail tests enforce this.

## One map
`src/lib/ownership.ts` maps `leads.assigned_to`, `deals.owner_id`,
`companies.account_owner`, `quotes.owner_id`. Every chip/lens reads and writes
through it — five hooks each knowing one column name is the drift shape.

## Create semantics
- Creator owns (human).
- **Inheritance outranks the creator**: deal on Anna's lead is Anna's even when
  an admin or FlowPilot typed it; quote inherits from the deal.
- Under service role the creator-fallback is off, but inheritance still applies
  (carrying an existing human decision is not guessing).

## Mine/All lens
One preference for the whole CRM in `profiles.preferences.ownership_lens`
(merge-written; NOT localStorage — that lost pinned pages on a domain change).
Defaults to **All**. Lists only — stat cards stay unlensed so two people see one
pipeline number. Mine with no uid degrades to everything, never to nothing.

## Coverage (`ownership_delegations`)
`to_user` acts for `from_user` between two dates. **Active is a date predicate,
no cron** (guardrail fails if `cron.schedule` appears). Ownership columns never
move — chip shows the owner + "covered by X". Coverage is given, never taken
(self-grant insert returns 42501). Both user FKs CASCADE.

Docs: `docs/architecture/ownership-and-coverage.md`
