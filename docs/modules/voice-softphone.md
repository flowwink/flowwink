---
title: "Voice / WebRTC Softphone"
description: End-to-end flow for the 46elks-integrated softphone — inbound routing, outbound dialling, voicemail and callbacks. Verified in production.
category: modules
---

# Voice / WebRTC Softphone

End-to-end flow for the 46elks-integrated softphone in FlowWink. Verified in
production (inbound + outbound + voicemail + callback).

## Architecture at a glance

```text
                       +----------------------+
External caller ──DID──▶ elks46-ingest (edge) ──connect──▶ Agent WebRTC user
                       +----------┬-----------+                 │
                                  │ no answer                   ▼ INVITE/SIP
                                  ▼                       Browser JsSIP
                          Voicemail flow                 (Softphone.tsx)
                                  │                            │
                                  ▼                            ▼
                            voice_calls ◀── realtime ─── IncomingCallToaster
```

The softphone is **mounted globally in `AdminLayout`** — one instance follows the
agent across every admin view. The Voice page and Contact Center only show
history and lists; the call controls themselves live in the floating widget in
the bottom-right corner.

## 46elks setup

| Component | What it is | Webhook |
|---|---|---|
| Public DID (`+46…`) | An ordinary mobile subscription. The only number external callers dial. | `voice_start` → `elks46-ingest` |
| WebRTC account (`46…`) | A SIP/WebRTC user (~30 SEK/month), one per agent. Not a real number. | `voice_start` → `elks46-ingest` (only needed for the green check in the 46elks UI) |
| `from_number` in `site_settings.integrations.elks46.config` | Caller ID for outbound calls. **Required** for outbound. | n/a |

## Inbound

1. `elks46-ingest` receives `voice_start` from 46elks and finds an online agent
   with `voice_enabled = true` in `support_agents`.
2. It returns `connect: "+46…"` in **phone format, not** a `sip:` URI — 46elks
   rejects SIP URIs with "not one of your allowed servers".
3. 46elks calls the agent's WebRTC account → JsSIP fires `newRTCSession` with
   `originator='remote'` → the softphone shows Answer / Decline.
4. `IncomingCallToaster` (also mounted globally in `AdminLayout`) subscribes to
   `voice_calls` realtime and shows a toast whose **Answer** button dispatches
   the `softphone:answer` window event.
5. On answer the SIP session reaches `confirmed` and `voice_calls` moves to
   `answered` → `completed`.
6. On no-answer (~15s) the flow falls through to voicemail (recording +
   transcription), visible under `/admin/voice` → Voicemail.

## Outbound

1. Any UI surface (CallbacksPanel, VoicemailPanel, CRM, manual dial-in in the
   widget) dispatches
   `window.dispatchEvent(new CustomEvent('softphone:dial', { detail: { number } }))`.
2. The softphone calls `elks46-ingest` with `{ action: 'call', mode: 'webrtc', to }`.
3. The edge function sets up two legs: it rings the agent's WebRTC account first,
   then `connect`s to `to`. `pendingOutboundRef` auto-answers the agent leg so the
   agent doesn't have to click twice.
4. The `voice_calls` row is logged with `direction='outbound'` at start-of-call.
5. Without `from_number` the edge function returns 500 with
   `"Missing caller number (configure from_number)"`. Configure it in
   `/admin/integrations` → the 46elks card.

## Global events

The softphone exposes two window CustomEvents:

| Event | Detail | Dispatched by |
|---|---|---|
| `softphone:dial` | `{ number: string }` | CallbacksPanel, VoicemailPanel, CRM action menus |
| `softphone:answer` | — | `IncomingCallToaster` (answer from the toast) |

These are deliberately loosely coupled — any view can start a call without
importing the softphone component.

## Recording playback

Recordings (voicemail) sit behind Basic Auth at 46elks. The client **never**
plays them straight from the 46elks URL — playback goes through the
`voice-recording` edge function, which authenticates server-side and streams the
audio back.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Calls go straight to voicemail | The toast was clicked but the widget never answered. Use the **Answer** button — the `softphone:answer` event performs the SIP accept. |
| `This SIP server is not allowed` | The `connect` target is `sip:…` instead of `+46…`. Routing must use phone format. |
| Outbound 500 `Missing caller number` | `from_number` missing in `site_settings.integrations.elks46.config`. |
| No softphone pill | The Voice module is disabled, or the agent lacks `voice_enabled = true` plus SIP credentials. |
| Two softphones at once | Should no longer happen — the local mounts in `VoicePage` and the Contact Center page were removed. Only `AdminLayout` mounts the softphone. |

## Files

- `src/components/admin/voice/Softphone.tsx` — JsSIP client, floating widget, event bus.
- `src/components/admin/voice/IncomingCallToaster.tsx` — global ring listener + toast.
- `src/components/admin/AdminLayout.tsx` — the global mount point.
- `supabase/functions/elks46-ingest/index.ts` — webhook router + outbound starter.
- `supabase/functions/voice-recording/index.ts` — recording playback proxy.
- `mem/voice/webrtc-softphone-flow.md` — short memory file for the agent.
