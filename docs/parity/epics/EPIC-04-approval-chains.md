---
title: "EPIC-04 — Multi-step approval chains"
status: planned
sprint: 1
owner: unassigned
category: parity
description: Lift approvals from single-role thresholds to sequential chains, any-of-N groups, delegation and expiry — back-filling purchasing, quotes, expenses and payroll.
---

# EPIC-04 — Multi-step approval chains

## Why
`approvals` today does single-role threshold routing. Real ERP controls need
**sequential chains** (manager → director → CFO), **groups** (any-of-N),
**delegation**, and **expiry/escalation**. Because `approvals` is a shared
primitive, lifting it once back-fills `purchasing`, `quotes`, `expenses` and
`payroll` at the same time. Independent of the other epics — can run in parallel.

## Outcome (Definition of Done for the whole epic)
- [ ] Capabilities → `done` in `approvals.json`: `approval_chains`, `approval_groups`,
      `delegation`, `expiration`
- [ ] `approvals` parity ≥ 60%
- [ ] Chain management + approve/reject are dual-surface (skills + admin UI)
- [ ] At least two consumer modules (`purchasing`, `expenses`) routed through chains
- [ ] `npx vitest run` + `npm run lint` green

## Capabilities delivered
| File | Capability id | From → To |
|---|---|---|
| `capabilities/approvals.json` | `approval_chains` | missing → done |
| `capabilities/approvals.json` | `approval_groups` | missing → done |
| `capabilities/approvals.json` | `delegation` | missing → done |
| `capabilities/approvals.json` | `expiration` | missing → partial |

## Issues

- [x] **04.1 — Chain & step data model** *(migration `20260610200000`)*
  - `approval_chains` + `approval_steps` (sort_order, role XOR group, min_approvals);
    `approval_requests.chain_id`/`current_step`; `approval_decisions.step_sort_order`.

- [x] **04.2 — Step advancement engine** *(`advance_approval_step`)*
  - Approving the current step advances `current_step`; `approved` only when the last
    step clears; any rejection stops the chain. Verified on scratch Postgres
    (step1→step2→approved, reject→rejected). → `approval_chains` = partial (routing/UI pending).

- [x] **04.3 — Approval groups (any-of-N)** *(`approval_groups` + members)*
  - A group step is satisfied when `min_approvals` **distinct** members sign (duplicate
    approvals from one user count once — verified 1/2→2/2). + `manage_approval_chain`
    skill (chains, steps, groups). → `approval_groups` = partial (admin UI pending).

- [x] **04.4 — Delegation** *(migration `20260611210000`; verified: delegate-without-role approved via delegation; revoke)*
  - **Migration/handler:** `approval_delegations` (from_user, to_user, start, end).
    Current approver resolution honours active delegations.
  - Flips `approvals.json#delegation` → done.

- [x] **04.5 — Expiry & escalation** *(escalate_after_hours + check_approval_escalations sweep; verified 10→20 + final-step logged)*
  - Step `deadline`; a sweep escalates to the next step or notifies on breach
    (reuse the `sla-check` sweep pattern). Scope: escalate-to-next only.
  - Flips `approvals.json#expiration` → partial.

- [x] **04.6 — Route purchasing + expenses through chains** *(DB gates: PO draft→sent + expense submitted→approved blocked until chain approved; request_entity_approval; verified end-to-end)*
  - `send_purchase_order` and `submit_expense_report` create chain-based requests
    when a matching `approval_chain` exists; fall back to single-rule routing otherwise.
  - **Verify:** a PO over threshold requires two sign-offs before `sent`.

## Dependencies & sequencing
04.1 → 04.2; 04.3/04.4/04.5 after 04.1; 04.6 last. Independent of EPIC-01/02/03.

## How we measure success
`parity-report.ts` shows `approvals` ≥ 60%. Integration test: a PO above the
two-step threshold cannot reach `sent` until both approvers sign.
