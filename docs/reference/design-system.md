---
title: Admin design system
description: The canonical page skeleton, header, save-button and settings-placement rules for every admin page.
category: reference
---

# Admin design system

One skeleton, one header, one save button. If a page deviates, the page is wrong —
not the system.

## Page skeleton

```tsx
<AdminLayout>                 {/* sidebar + top bar + p-8 padding. Never add your own container/padding. */}
  <AdminPageContainer>        {/* space-y-6 rhythm, optional maxWidth */}
    <AdminPageHeader … />     {/* the page's only <h1> */}
    …content…
  </AdminPageContainer>
</AdminLayout>
```

- **Never** add `container mx-auto p-6` inside `AdminLayout` — `<main>` already has `p-8`.
  Double padding was the single most common layout drift (fixed 2026-08-08 on 9 pages).
- Full-height "app" surfaces (FlowPilot cockpit, POS, FlowChat, Flowtable, editors)
  are allowed to own their chrome. They still use the canonical `<h1>` typography.

## Header

`<AdminPageHeader />` (`src/components/admin/AdminPageHeader.tsx`) is the only place an
admin `<h1>` may live.

| Prop | Use |
|---|---|
| `title` | Sentence case. Renders `font-serif text-2xl font-bold`. |
| `description` | One line, `text-sm text-muted-foreground`, max-w-2xl. |
| `icon` | Optional lucide component, `h-6 w-6 text-muted-foreground`. |
| `children` | **Max 2 primary actions.** Rightmost = the primary one. |
| `secondaryActions` | Everything rare — exports, audits, docs links, danger zone. Collapses into a `…` menu. |
| `backAction` | Detail/editor pages. Never hand-roll a "Back" button next to the title. |

**Show the essential, hide the rest.** If the header grows past two buttons, the extras
belong in `secondaryActions`, in a tab, or in the module's settings drawer.

## Save

`<SaveButton />` (`src/components/admin/SaveButton.tsx`) — always top-right in the header,
never a second save further down the page.

- Wording is always **"Save changes"**. Not "Save Changes", not "Save settings", not "Update".
- `hasChanges` renders the dirty dot; pair it with `useUnsavedChanges` for the leave guard.
- Dialogs are the exception: a plain `Cancel` / `Save` pair in `<DialogFooter>` is correct.

## Where settings live

Three tiers, in this order of preference:

1. **Module page** — configuration that *shapes the module's own data*: pipeline stages,
   carrier rate cards, booking availability, dunning thresholds, ticket types. It sits
   next to the records it shapes, so the operator discovers it while working.
   A small "Config"/"Stages" button on the module page is the intended pattern.
2. **Integration** — anything tied to an external account: credentials, mailbox identity,
   provider selection. Lives in Integrations, never duplicated into Settings.
3. **Site Settings** — platform-wide only: locale, currency, branding, SEO, cookie banner.

Rule of thumb: *if turning it off changes how records look, it belongs in the module.
If it changes how the whole instance behaves, it belongs in Settings.*

## Discoverability

Every route registered in `App.tsx` must be reachable by clicking, from either
`adminNavigation.ts` or a parent page. A route with no click path is a bug, not a
"hidden gem". Ten of them were found and linked on 2026-08-08 (Pricelists, Shipping,
Returns, Payroll, Fixed Assets, Currencies, Visitor Intelligence, Social posts,
Quote templates, POS Audit).

`navigationGroups` is also the route gate (`admin-route-access.ts`), so an unlisted page
is invisible **and** access-denied for non-admins. Nav items are gated by `moduleId`
(module enabled) and `allowedRoles` (functional role).
