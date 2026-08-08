---
name: Admin design system
description: Canonical admin page skeleton, AdminPageHeader/SaveButton rules, settings placement tiers, and the no-orphan-route rule.
type: design
---

## Canonical skeleton
`AdminLayout` → `AdminPageContainer` → `AdminPageHeader` → content.
`AdminLayout`'s `<main>` already has `p-8` — never add `container mx-auto p-6` inside it (double padding).

## Header
`AdminPageHeader` owns the page's only `<h1>` (`font-serif text-2xl font-bold text-foreground`).
Props: `title`, `description`, `icon`, `children` (max 2 primary actions), `secondaryActions` (overflow `…` menu for rare actions), `backAction`.
Never hand-roll an `<h1>` or a Back button on an admin page. Full-height app surfaces (POS, FlowChat, Flowtable, FlowPilot cockpit, editors) may own their chrome but keep the same h1 typography (`text-lg` variant allowed in compact toolbars).

## Save
`SaveButton` (`src/components/admin/SaveButton.tsx`), always top-right in the header, label always **"Save changes"**, dirty dot via `hasChanges`, leave guard via `useUnsavedChanges`. Only one save per page. Dialogs keep `Cancel`/`Save` in `DialogFooter`.

## Settings placement (three tiers)
1. **Module page** — config that shapes the module's own data (pipeline stages, carrier rate cards, dunning thresholds). A "Config"/"Stages" button on the module page is the intended pattern.
2. **Integration** — anything tied to an external account/credentials.
3. **Site Settings** — platform-wide only (locale, currency, branding, SEO).
Rule: changes how records look → module. Changes how the instance behaves → Settings.

## No orphan routes
Every `/admin/*` route in `App.tsx` must be clickable from `adminNavigation.ts` or a parent page. `navigationGroups` doubles as the route gate (`admin-route-access.ts`), so unlisted pages are also access-denied for non-admins.

Full write-up: `docs/reference/design-system.md`.
