# FlowWink — PRD

Levande produktkravsdokument. Nya moduler, block och features dokumenteras här när de tillkommer. Konsolidera mot `docs/modules/` när omfattningen växer.

---

## Voice (ny modul, v0.1.0)

### Problem

Live Support hanterar idag text (web chat, Telegram, SMS via 46elks). Visitors som vill prata — supportärenden, säljförfrågningar — har ingen väg in. Telefonnummer är fortfarande den vanligaste "ring oss"-CTA:n på företagswebbar i Norden.

### Mål

Lägga till röst som en första-klassens kanal i Live Support, utan att låsa plattformen till en specifik telecom-provider. Open-source-projektet ska fungera på vilken marknad som helst — `elks46` för Norden, `twilio` för globalt, fler kommer.

### Scope (fas 1 — MVP)

Se [docs/modules/voice.md](docs/modules/voice.md) för fullständiga use cases (UC1–UC4) och fas-plan.

**Levereras nu:**
- Pluggable provider-arkitektur (`VoiceProvider`-kontrakt + adapter-registry)
- 46elks-adapter (komplett), Twilio-adapter (stub som bevisar kontraktet)
- Provider-agnostisk edge function `voice-ingest`
- Tabell `voice_calls` + utökning av `support_agents` med SIP/mobil-fält
- 3 MCP-exponerade skills: `list_voice_calls`, `schedule_voice_callback`, `mark_voice_callback_done`
- Modul-registrering med opt-in via `voice` flag i `ModulesSettings`

**Kommer i fas 2/3:**
- Browser WebRTC-klient i admin (jssip mot 46elks SIP-WSS)
- Voicemail-transkription via STT
- UC4: booking-IVR med slot-förslag
- Realtime AI voice agent (WebSocket-stream)
- Full Twilio + fler providers

### Designprinciper

- **Decoupling:** voice-modulen och live-support importerar inte varandra. Kommunikation via platform event bus (`voice.call.*`).
- **Provider-neutralitet:** All UI, routing, voicemail-kö, callback-flöde är gemensam kod. Bara transport-lagret (parse + serialize) skiljer sig per provider.
- **Capability-gated UI:** WebRTC-knapp visas bara om vald providers `capabilities.webrtc === true`. Fallback: forward-to-mobile fungerar för alla providers.
- **+1 edge function totalt.** Provider-val sker i kod, inte via separata functions.

### Senare-att-dokumentera

Detta dokument kompletteras när fas 2 levereras (WebRTC-klient, transkription, IVR).

## WebMeet (video meetings)

Quick 1-to-few video meetings with shareable URLs — like Google Meet, built in. See [docs/modules/webmeet.md](docs/modules/webmeet.md).

**What ships now:**
- `webmeet_rooms` table (slug, name, host, password, max_participants, expires_at, ended_at).
- Hook `useWebmeet` — browser-native `RTCPeerConnection` mesh over Supabase Realtime broadcast (`webmeet:<slug>`), with presence sync and screen-share track-replacement.
- Admin page `/admin/webmeet` — list + create rooms, copy link.
- Public page `/meet/:slug` — anonymous-friendly lobby → join → grid + mic/cam/screen-share/end controls.
- 3 MCP-exposed skills: `create_webmeet_room`, `end_webmeet_room`, `list_webmeet_rooms`. FlowPilot and external agents can mint a meeting URL and share it.
- Module flag `webmeet` in `ModulesSettings` (opt-in, default off).

**Design principles:**
- **No SFU.** Peer-to-peer mesh — works up to ~6 participants. Larger broadcasts go to `webinars` (planned LiveKit/Agora runtime).
- **No signaling tables.** Realtime broadcast carries SDP + ICE.
- **Public-safe.** Anonymous guests can read an active room row and join the channel — only authenticated users can create or end rooms.
- **MCP-first.** Any agent (FlowPilot, OpenClaw peers, marketing claw) can create a meeting URL via the same skill the admin UI uses.

**Later:**
- Invite fan-out — auto-send the join link via email / SMS / Telegram (per `mem/features/webinars-and-webmeet-plan.md`).
- Optional TURN config per site.
- Optional recording → push to `documents`.

## Admin Dashboard (role-aware)

The dashboard is a widget surface tuned per functional role instead of one CMS-centric page for everybody.

**What ships now:**
- **Widget catalog** — `src/lib/dashboard-presets.ts` holds all 20 widgets with `moduleId` (module toggle gating) and `roles` (relevance gating). Admin sees everything, same super-role rule as the sidebar.
- **Role presets** — one widget set + order per role (`admin`, sales, marketing, support, accounting, hr, warehouse, purchasing, projects). Admins can apply another role's preset from Customize.
- **My Day** (`MyDayWidget.tsx`) — cross-module personal queue: CRM tasks, project tasks and tickets assigned to the signed-in user plus pending approvals, deadline-sorted with overdue in red. Complements Needs Attention, which is org-wide.
- **Module KPI widgets** (`ModuleDashboardWidgets.tsx`, shared chrome in `DashboardWidgetShell.tsx`) — Receivables, Support Queue, Approvals, Inventory, Purchasing, People, Projects. Read-only aggregates, every tile deep-links into its module.
- **Persistence** — `user_dashboard_layouts (user_id, preset_key, widgets jsonb)`, RLS scoped to `auth.uid()`. `localStorage` remains a first-paint cache; the DB row is the source of truth so a layout follows the user across browsers.

**Design principles:**
- Widgets never own business logic — they read aggregates and link into the module.
- Layout is stored per user AND per preset key, so "View as role" shows the previewed role's dashboard rather than the admin's saved one.
- A widget hidden by role relevance is also hidden in Customize — no dead toggles.
