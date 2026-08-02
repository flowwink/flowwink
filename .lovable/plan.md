# PEPPOL e-invoicing — access-point integration for invoicing

## Why

Since 1 April 2019 every invoice to the Swedish public sector (state, kommun, region)
must be a structured e-invoice per the European standard — in practice PEPPOL BIS
Billing 3.0. A PDF over email does not count. Today FlowWink cannot legally invoice a
kommun. This is the only *legal* blocker in the parity program, so it goes before the
remaining depth work.

An SMB does not become its own PEPPOL access point. They open an account with an
operator (Storecove, InExchange, Qvalia, Pagero), get an API key, and we send through
it — the same shape as Resend for email.

## Architecture decision

Not a new domain module. Two existing patterns:

- **Format** belongs to invoicing/accounting, like the BAS 2024 chart lives in the
  locale pack. Serialising an invoice to UBL 2.1 is a *document profile*, not a
  separate invoicing system.
- **Transport** is an integration per `docs/architecture/channel-adapter-contract.md`:
  one adapter behind a contract, credentials in integration settings, provider
  swappable.

So: a `peppol` module at integration tier, depending on `invoicing`, toggled off until
a key exists (Law 4 — fail forward, don't gate). Customers who never invoice the public
sector never see it.

```text
invoice ──> UBL 2.1 generator ──> BIS Billing 3.0 validation ──> access-point adapter
             (pure, testable)        (rejects before send)         (Storecove REST)
                                                                        │
                                          invoice.peppol_status <───── kvittens
                                       sent → delivered | rejected(reason)
```

## Delivery order

**1. UBL 2.1 generator + BIS Billing 3.0 validation** *(no vendor account needed)*
Pure functions mapping an invoice + its lines to UBL XML: seller/buyer PEPPOL IDs, VAT
category codes, payment means, line and total arithmetic. A validation pass that
returns structured errors (missing buyer ID, VAT code mismatch, totals that don't sum)
before anything leaves the system. Unit tests with a golden-file fixture per case:
domestic 25% VAT, reverse charge, zero-rated.

**2. Participant identity**
`companies` gets a `peppol_id` field (Swedish form `0007:5561234567`, derived from
`org_number` when absent). A lookup skill resolves an org number to a PEPPOL
participant via the operator's SMP so staff can confirm a kommun is reachable before
invoicing.

**3. Access-point adapter (Storecove)**
Storecove first: plain REST, no certification required. An edge function holding the
send + status-poll calls, credentials read server-side from integration settings. The
adapter interface is what a second provider would implement — no Storecove types leak
into invoicing.

**4. Invoice lifecycle + agent skills**
`delivery_method` gains `peppol` next to `email`/`pdf`. The invoice carries
`peppol_status`, the operator's document id, and the rejection reason when there is
one, with retry after a fix. Skills `send_einvoice` and `check_einvoice_status`
exposed over MCP so FlowPilot and external operators can drive it.

**5. Admin surface + docs**
A PEPPOL card in integration settings (key, connected identity, "check connection"),
matching the Composio card's identity-first pattern. Send-via-PEPPOL action on the
invoice with the validation errors shown inline rather than a bare failure. Capability
flips in `docs/parity/capabilities/invoicing.json`, module doc, and a note in the
quote-to-cash process doc.

## Technical notes

- Migration adds `companies.peppol_id`, invoice PEPPOL columns, and a small
  `einvoice_transmissions` audit table. Idempotent and forward-dated per project rule.
- RLS: transmissions readable by admin/accounting, writes only via the sending RPC and
  service role. GRANTs stated in the same migration.
- The generator lives in shared code so both the edge function and the frontend
  validation preview use one implementation — no second XML builder.
- Steps 1 and 2 are fully deliverable and testable now. Step 3 needs a Storecove
  account before it can be verified live; the adapter can be written and unit-tested
  against recorded responses in the meantime.

## Scope boundary

Outbound invoicing to the public sector. Inbound e-invoice receipt (supplier invoices
arriving over PEPPOL into procure-to-pay) is a natural follow-on and reuses the same
account, but it is not in this delivery.
