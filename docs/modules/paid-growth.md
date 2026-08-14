---
title: "Growth Module"
module_id: "paidGrowth"
version: "2.0.0"
category: "insights"
autonomy: "agent-capable"
manual: true
description: Campaigns author the message once; the channel rails deliver it — social queue with real LinkedIn publishing, blog and newsletter drafts behind their own gates.
---

# Growth — Campaigns & Social Publishing

> **Status:** manually maintained — describes the process as verified live
> (first campaign-born LinkedIn post, 2026-08-14). The auto-generator skips
> this file. **Source of truth:** `src/lib/modules/growth-module.ts` + this file.

Growth is two surfaces with one principle: **the campaign owns the message and
the decision; each channel rail owns delivery with the gate that matches its
blast radius.**

## The campaign flow (create once, publish everywhere)

```
Campaigns (Content Hub)
  ├─ research the topic → content angles + hooks (saved, reusable)
  ├─ pick an angle → AI generates per-channel variants in ONE voice
  │    grounded in: Business Identity (always) + published knowledge on the
  │    topic (Knowledge Recycling — retrieved with a VISITOR's eyes, so
  │    internal material can never leak into outward copy) + the last 15
  │    published pieces (anti-repetition). Your brief overrides defaults.
  ├─ review, edit, pick a featured image (per-channel overrides supported)
  ↓
APPROVE  ← the decision. Fan-out materializes:
  ├─ linkedin/x/instagram/facebook → Social Posts queue
  │     campaign-linked, image inherited, scheduled if the campaign has a time
  ├─ blog       → blog post DRAFT   (a human publishes from the blog surface)
  ├─ newsletter → newsletter DRAFT  (sending stays behind the send gate:
  │                                  recipients, test send, send)
  └─ re-approving returns existing artifacts — nothing duplicates
```

## The social queue (delivery)

Social Posts is the **scheduler and executor**. Every 15 minutes a sweep
publishes due posts:

- **LinkedIn** publishes for real via Composio (`LINKEDIN_CREATE_LINKED_IN_POST`,
  signed with the connected account's author URN) → status `posted` + the
  external post URL. Connect the account via **Modules → Composio → Quick
  Connect → LinkedIn** — the connection must be made through FlowWink (it
  lands under the entity the publisher looks up), not in Composio's dashboard.
- Channels without a connected publisher are marked **failed with the reason**
  — the queue never lies and never grows unbounded.
- **Scheduling IS the approval**: only `scheduled` posts with a passed time
  are touched; drafts are never published.

Ad-hoc posts (no campaign) use the same queue — two doors, one rail.

## Why the channels behave differently after Approve

That asymmetry is the design, not a seam: a social post's blast radius is one
feed (schedule = consent), a blog post is your permanent public record (a human
presses Publish), a newsletter hits every subscriber's inbox (its own send
flow). One decision, three rails, three proportionate gates — the same shape as
propose → approve → voucher in accounting.

## Ads (the original surface)

Ad campaign skills (`ad_campaign_create`, `ad_creative_generate`,
`ad_performance_check`, `ad_optimize`, `get_attribution_report`) manage paid
campaigns and last-touch UTM attribution. Note: `social_posts.campaign_id`
refers to **content campaigns** (content_proposals), not ad campaigns.
