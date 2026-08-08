---
title: "Ownership & coverage"
description: Shipped 2026-08-07 in four steps (#166–#169). 
category: architecture
---

# Ownership & coverage

> Who owns a record, how that answer travels down the chain, and how a colleague
> covers for you without anything being moved.

Shipped 2026-08-07 in four steps (#166–#169). This page is the source of truth;
module docs link here and do not restate it.

## The law: ownership is a lens and a label, never a security boundary

Ownership columns are for **focus and accountability**. RLS must never reference
them. Odoo wires "my records" into record rules — which is where salespeople stop
seeing each other's pipelines and start calling the same customer twice. In
FlowWink, access is decided by the **vertical** axis (which modules a functional
role may open) and rows are never hidden on the **horizontal** axis (who owns
them). A guardrail forbids ownership columns appearing in any migration's
policies, forever.

## One map, three spellings

The same idea already lived under three column names, and every wire identifier
stays as it is (fix the story, not the wire). `src/lib/ownership.ts` holds the
one map every surface reads and writes through:

| Entity | Owner column |
|---|---|
| `leads` | `assigned_to` |
| `deals` | `owner_id` |
| `companies` | `account_owner` |
| `quotes` | `owner_id` (added 2026-08-07, `ON DELETE SET NULL`) |

Five hooks that each know one column name is the drift shape this codebase keeps
finding — hence the map.

## Ownership on create, and inheritance down the chain

- **Creator owns.** A human who creates a lead/deal/quote owns it, and the
  `OwnerChip` shows it — nothing hides.
- **Inheritance outranks the creator.** A deal created on Anna's lead is Anna's,
  even when an admin or FlowPilot typed it: the relationship owner, not the
  typist. The quote on that deal is Anna's too. One decision, made once, at the
  top of the chain.
- **The agent never guesses.** Under the service role the creator-fallback is
  off, but inheritance still applies — a human decision already exists, so
  carrying it is not guessing. An agent creating an *orphan* deal leaves it
  unowned.

## The Mina/Alla lens

One toggle in the headers of Contacts, Deals, Companies and Quotes, applied via
`applyLens()` through the same map the chip writes through — so the lens and the
chip can never disagree about which column ownership lives in.

- **One preference for the whole CRM**, not one per list: "Mine" is a mode of
  looking. Stored in `profiles.preferences` (key `ownership_lens`),
  merge-written so it never clobbers a sibling key.
- Not `localStorage`: that is per browser per origin, and it lost everyone's
  pinned pages the day an instance got its real domain.
- **Defaults to All.** Transparency is the purpose; focus is the exception you
  opt into.
- **Lists only.** Stat cards keep their own unlensed query — two people looking
  at the pipeline total must see one number.
- Unassigned rows disappear under Mine, honestly: they are nobody's, and one
  chip click makes them yours.
- Mine with no uid degrades to *everything*, never to nothing — a slow auth load
  must not blank the CRM.

Pure frontend. The moment this feature needs a migration, someone is about to
put the lens into RLS.

## Coverage (`ownership_delegations`)

Vacation coverage without mass reassignment. One row says: `to_user` acts for
`from_user` between two dates.

- **Active is a date predicate, not a state.** No cron flips anything; the row
  simply stops matching on `ends_on + 1`. Nothing to clean up, nothing to go
  stale — a guardrail fails if `cron.schedule` ever appears in the migration.
- The Mina lens includes owners I currently cover, and the toggle reads
  **"Mine (+1)"** so the covering colleague sees they are carrying someone.
- **Ownership columns never move.** The chip keeps showing Björn with a
  "covered by Anna" hint — a silently swapped name would hide exactly the fact
  colleagues need.
- **Coverage is given, never taken.** The covered person or an admin writes it;
  the covering colleague cannot grant themselves reach (verified live: the
  self-grant insert returns `42501`). Self-coverage is rejected by CHECK.
- Readable by every authenticated colleague — who covers whom is office-level
  truth.
- Both user FKs `CASCADE`: a delegation is a pointer between two people, not
  business history, and unlike a contract it does not outlive its parties.

## Files

| Purpose | Path |
|---|---|
| Ownership map + lens | `src/lib/ownership.ts` |
| Lens preference + active delegations | `src/hooks/useOwnershipLens.ts` |
| Owner chip / lens toggle / coverage dialog | `src/components/admin/OwnerChip.tsx`, `LensToggle.tsx`, `CoverageDialog.tsx` |
| Guardrails | `src/lib/__tests__/ownership-*.guardrails.test.ts` |
| Migrations | `20260808300000` (ownership), `…310000` (inheritance), `…330000` (delegations) |
