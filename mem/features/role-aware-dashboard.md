---
name: Role-aware Admin Dashboard
description: Widget catalog + role presets, My Day personal queue, module KPI widgets, layout persisted in user_dashboard_layouts.
type: feature
---

## Source of truth
- Catalog + presets: `src/lib/dashboard-presets.ts` (`DASHBOARD_WIDGETS`, `ROLE_PRESETS`, `isWidgetRoleRelevant`, `presetKeyForRoles`, `buildPresetLayout`).
- Layout state: `src/hooks/useDashboardLayout.ts`. Two-tier storage — `localStorage` for first paint, `user_dashboard_layouts (user_id, preset_key, widgets jsonb)` as source of truth (RLS `user_id = auth.uid()`).
- Layout key = user + preset key, so role preview shows the previewed role's dashboard.

## Widgets
- Personal queue: `MyDayWidget.tsx` — assigned `crm_tasks`, `project_tasks`, `tickets` (+ pending `approval_requests`), sorted by deadline.
- Module KPIs: `ModuleDashboardWidgets.tsx` — Receivables, Support Queue, Approvals, Inventory, Purchasing, People, Projects. Shared chrome in `DashboardWidgetShell.tsx` (`WidgetShell`, `MetricTile`).
- Gating is two-dimensional: `moduleId` (module enabled) AND `roles` (role relevance). Admin bypasses role gating.

## Gotchas
- Supabase PostgrestBuilder is lazy — `void supabase.from(...).upsert(...)` never executes. Consume it (`.then()` / await).
- Tickets have `sla_deadline`, not `due_at`.
- Adding a widget = catalog entry + `moduleAvailable` map entry + `renderWidget` case in `AdminDashboard.tsx`.
