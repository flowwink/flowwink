---
title: "Reference"
description: Lookup material — developer commands, module API contracts, the headless HTTP surface, the skill registry and FlowPilot slash commands.
category: reference
---

# Reference

Lookup material. Nothing here tells a story — read [`../start-here.md`](../start-here.md) for that.

| Doc | What you'll find |
|---|---|
| [`developer-commands.md`](./developer-commands.md) | Every npm/bun script: build, tests, skill sync, docs generation, parity, deploy |
| [`module-api.md`](./module-api.md) | The `ModuleDefinition` contract every module implements |
| [`headless-api.md`](./headless-api.md) | Content and execute endpoints for using FlowWink headlessly |
| [`skills-source.md`](./skills-source.md) | Where skills are defined in code and how they reach `agent_skills` |
| [`commands.md`](./commands.md) | Slash commands inside FlowPilot chat (`/status`, `/briefing`, …) |

Per-module contracts, tables and webhook events live in the
[module catalog](../modules/index.md) — generated from code, so it is never stale.
