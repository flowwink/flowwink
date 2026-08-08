---
title: "FlowWink Documentation"
description: Structure inspired by OpenClaw.
category: general
---

# FlowWink Documentation

> A modular, self-hosted **Business Operating System**. Modules, skills, automations and MCP work standalone — the autonomous operator (**FlowPilot**, OpenClaw, Claude Desktop, or any MCP client) is opt-in.

Structure inspired by [OpenClaw](https://github.com/openclaw/openclaw).

> **New here?** Read [`start-here.md`](./start-here.md) — 5-minute orientation.

---

## Two audiences, two paths

| You are… | Start here |
|---|---|
| **Operator** — running FlowWink for a business | [`operators/`](./operators/README.md) → install, configure modules, drive day-to-day work |
| **Builder** — extending or contributing to FlowWink | [`builders/`](./builders/README.md) → add modules, blocks, skills, templates |
| **Agent developer** — connecting an MCP client | [`mcp/getting-started.md`](./mcp/getting-started.md) → 5-min setup for Claude / OpenClaw / custom |

Both paths share the **concepts** below. Everything else (guides, modules, reference, processes) is referenced from the two landing pages.

---

## Concepts — read these first (both audiences)

| Doc | Why |
|---|---|
| [`concepts/elevator-pitch.md`](./concepts/elevator-pitch.md) | One-page positioning |
| [`architecture/agent-harness.md`](./architecture/agent-harness.md) | **The agent harness** — the named platform spine (loop, skill-select, policy, verify, self-correct, escalate, learn, observe) that FlowPilot *and* external agents run on |
| [`architecture/agent-resumption.md`](./architecture/agent-resumption.md) | **Resumption (H11)** — how a paused multi-step run continues from its checkpoint; the Trace's run identity, read the other way |
| [`concepts/operator-strategy.md`](./concepts/operator-strategy.md) | Why FlowPilot is a module, not the core |
| [`concepts/openclaw-law.md`](./concepts/openclaw-law.md) | The 10 inviolable agentic laws |
| [`concepts/flowchat-vs-flowpilot.md`](./concepts/flowchat-vs-flowpilot.md) | Utility AI vs operator AI |
| [`architecture/ownership-and-coverage.md`](./architecture/ownership-and-coverage.md) | **Ownership** — the one map, inheritance down the chain, the Mine/All lens, vacation coverage, and why ownership is never RLS |
| [`processes/sign-to-serve.md`](./processes/sign-to-serve.md) | **Sign-to-serve** — signed contract → service → portal → ticket, and the one-invoicer rule |
| [`operators/users-access-and-invites.md`](./operators/users-access-and-invites.md) | **Users & access** — invites via your own email rail, functional roles, route gating, deleting a user |
| [`operators/comparison.md`](./operators/comparison.md) | FlowWink vs Odoo / HubSpot / NetSuite |
| [`concepts/prd.md`](./concepts/prd.md) | Full system reference — modules, processes, scope |

---

## Folder map

| Folder | Contents | Audience |
|---|---|---|
| [`concepts/`](./concepts/) | Architecture, vision, laws | both |
| [`operators/`](./operators/README.md) | Install, configure, run | operators |
| [`builders/`](./builders/README.md) | Extend, contribute, test | builders |
| [`guides/`](./guides/) | Docker, deploy, migrate, maintain, integrations | operators |
| [`modules/`](./modules/) | One page per module — auto-generated from `defineModule()` | both |
| [`processes/`](./processes/) | End-to-end flows (lead-to-customer, quote-to-cash, …) | both |
| [`pilot/`](./pilot/) | FlowPilot internals — handlers, memory, heartbeat | builders |
| [`architecture/`](./architecture/) | Platform layers (MCP, event bus, locale packs, tiers) | builders |
| [`reference/`](./reference/) | Module API, headless REST/GraphQL, skill registry, commands | both |
| [`mcp/`](./mcp/) | MCP resources for external agents | builders |
| [`agents/`](./agents/) | Department-claw playbooks (sales / marketing / finance / ops / support / success) | operators |
| [`contributing/`](./contributing/) | How to contribute, run tests | builders |

---

## Integration guides

| Doc | Why |
|---|---|
| [`guides/composio-gmail-sync.md`](./guides/composio-gmail-sync.md) | How the Gmail/Composio inbound and outbound mail flow works |

---

## Quick links

- **67 modules** registered in `src/lib/modules/` — every one has a page in [`modules/`](./modules/) (alias-aware via `scripts/check-doc-drift.ts`)
- **8 business processes** documented in [`processes/`](./processes/)
- **6 department-claw playbooks** in [`agents/`](./agents/) for external MCP operators
- Public docs portal: [/docs](https://flowwink.com/docs) (auto-synced from this folder, with embedded AI chat)

---

*Edit any page on GitHub → push → an admin runs the sync from `/admin/docs` (or wait for the scheduled sync).*

*Convention: docs are updated **in place** to describe the current state. Plan/sprint documents carry a `status` field in their frontmatter (`planned` / `active` / `completed`) plus a dated outcome note when done — we don't archive; we describe what we have now.*
