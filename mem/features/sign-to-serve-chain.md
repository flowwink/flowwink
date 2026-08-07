---
name: sign-to-serve chain
description: Signed contract mints a service (provider='contract') + portal account; the one-invoicer rule keeps contract-born services off the subscription cron
type: feature
---

# Sign-to-Serve

Quote → contract (§4 lines, §5 term) → send for signature (`comms-send` handler
`contract_email`, branded shell, link from `general.siteUrl` + contract token) →
`contract-sign` → `create_subscription_from_contract` + `provision-portal-account`
→ `/account/activate` (email read-only) → **My services** → ticket carrying
`subscription_id`.

## One-invoicer rule (structural, guardrailed)
- Contract-born service is stamped `provider = 'contract'`.
- `subscription-billing-cron` bills `provider = 'manual'` only.
- `contract-billing-cron` keeps billing the contract. Nothing double-bills.
- `src/lib/__tests__/service-chain.guardrails.test.ts` fails if the cron filter
  widens or the birth function stops stamping `'contract'`.

## Consequences
- Stripe-only row actions (customer portal) must not render for `contract` rows.
- `change_subscription` proration = `manual` rows; contract services change via
  the agreement.
- `create_subscription_from_contract` is idempotent (unique index on
  `subscriptions(contract_id)`); `contract-sign` logs but never throws on
  service/portal failure — a failed signature is worse than a failed follow-up.

## Two dials, not a module split
`store.storefront` hides the cart; `customer_portal.enabled` hides the public
account entrance. A service business runs ecommerce with the storefront off.
Portal invites are gated by `customer_portal.enabled`, NOT `allowSelfSignup`.

Docs: `docs/processes/sign-to-serve.md`
