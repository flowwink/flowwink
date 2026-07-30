/**
 * composio-webhook — public endpoint Composio calls when a watched Gmail mailbox
 * receives a new message (Pub/Sub push, wrapped by Composio).
 *
 * Flow:
 *   1. Verify Composio signature (if COMPOSIO_WEBHOOK_SECRET set).
 *   2. Extract message_id + connected_account_id from payload.
 *   3. Look up our inbound_email_accounts row → email_address.
 *   4. Call composio-proxy { action: 'gmail_get' } to expand the message.
 *   5. Update last_received_at / last_history_id on the account.
 *   6. emit_platform_event('email.received', { ... }) — event-dispatcher
 *      then fans out to whatever automations the operator has enabled.
 *
 * No JWT verification — Composio is the caller. Idempotency happens downstream
 * (email_to_ticket dedupes on tickets.source_id).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { resolveInboundEntity } from '../_shared/email/resolve-entity.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-composio-signature, x-signature, webhook-signature, webhook-id, webhook-timestamp',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WEBHOOK_SECRET = Deno.env.get('COMPOSIO_WEBHOOK_SECRET') || '';

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

function constantTimeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const left = enc.encode(a);
  const right = enc.encode(b);
  if (left.length !== right.length) return false;

  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

function toBase64(bytes: ArrayBuffer): string {
  let binary = '';
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function hexDecode(s: string): Uint8Array | null {
  if (!/^[0-9a-fA-F]+$/.test(s) || s.length % 2 !== 0) return null;
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
  return out;
}

function base64Decode(s: string): Uint8Array | null {
  try {
    const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/'));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

async function signWith(keyBytes: Uint8Array, value: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
}

async function verifySignature(req: Request, rawBody: string): Promise<boolean> {
  if (!WEBHOOK_SECRET) return true;

  const webhookSignature = req.headers.get('webhook-signature');
  const webhookId = req.headers.get('webhook-id');
  const webhookTimestamp = req.headers.get('webhook-timestamp');
  const legacySignature = req.headers.get('x-composio-signature') || req.headers.get('x-signature');

  // Candidate key encodings — Standard Webhooks uses whsec_<base64>; Composio docs vary.
  const secret = WEBHOOK_SECRET.replace(/^whsec_/, '');
  const keyCandidates: { label: string; bytes: Uint8Array }[] = [
    { label: 'raw', bytes: new TextEncoder().encode(WEBHOOK_SECRET) },
    { label: 'raw-no-prefix', bytes: new TextEncoder().encode(secret) },
  ];
  const hex = hexDecode(secret);
  if (hex) keyCandidates.push({ label: 'hex', bytes: hex });
  const b64 = base64Decode(secret);
  if (b64) keyCandidates.push({ label: 'base64', bytes: b64 });

  if (webhookSignature && webhookId && webhookTimestamp) {
    const numericTimestamp = Number(webhookTimestamp);
    const timestampMs = Number.isFinite(numericTimestamp)
      ? numericTimestamp * 1000
      : Date.parse(webhookTimestamp);
    if (Number.isFinite(timestampMs) && Math.abs(Date.now() - timestampMs) > 300_000) {
      console.warn('[composio-webhook] timestamp out of tolerance');
      return false;
    }

    const signed = `${webhookId}.${webhookTimestamp}.${rawBody}`;
    const received = webhookSignature
      .split(/\s+/)
      .map((p) => (p.includes(',') ? p.split(',', 2)[1] : p))
      .filter(Boolean);

    for (const k of keyCandidates) {
      const mac = await signWith(k.bytes, signed);
      const b64sig = toBase64(mac);
      const hexsig = toHex(mac);
      for (const r of received) {
        if (constantTimeEqual(b64sig, r) || constantTimeEqual(hexsig, r)) {
          console.log('[composio-webhook] signature ok via', k.label);
          return true;
        }
      }
    }
    console.warn('[composio-webhook] no key candidate matched. received=', received.map((r) => r.slice(0, 8) + '...').join(','), 'tried=', keyCandidates.map((k) => k.label).join(','));
    return false;
  }

  if (legacySignature) {
    const stripped = legacySignature.replace(/^sha256=/, '');
    for (const k of keyCandidates) {
      const mac = await signWith(k.bytes, rawBody);
      if (constantTimeEqual(toHex(mac), stripped) || constantTimeEqual(toBase64(mac), stripped)) return true;
    }
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);

  const rawBody = await req.text();
  const sigOk = await verifySignature(req, rawBody);
  if (!sigOk) {
    console.warn('[composio-webhook] signature mismatch');
    return json({ error: 'invalid signature' }, 401);
  }

  let body: any;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return json({ error: 'invalid JSON' }, 400);
  }

  console.log('[composio-webhook] payload:', JSON.stringify(body).slice(0, 800));

  // Composio Gmail webhook payload shape (best-effort across formats):
  //   { type: 'GMAIL_NEW_MESSAGE', data: { message_id, thread_id, connected_account_id, ... } }
  // We accept several aliases since Composio renames fields between versions.
  const triggerSlug = body?.metadata?.trigger_slug || body?.triggerSlug || body?.trigger_slug || body?.type;
  if (triggerSlug && !String(triggerSlug).toLowerCase().includes('gmail')) {
    return json({ ok: true, ignored: `unsupported trigger ${triggerSlug}` });
  }

  const data = body?.data || body?.payload || body;
  const messageId = data?.message_id || data?.messageId || data?.id || data?.message?.id || data?.email?.id;
  const threadId = data?.thread_id || data?.threadId || data?.thread?.id || data?.message?.threadId || data?.email?.threadId;
  const connectedAccountId =
    body?.metadata?.connected_account_id ||
    data?.connected_account_id ||
    data?.connectedAccountId ||
    body?.connected_account_id ||
    body?.connectedAccountId;
  const historyId = data?.history_id || data?.historyId || null;

  if (!messageId) {
    // Some Pub/Sub deliveries are heartbeat-style (no message_id). ACK so Composio
    // doesn't retry; nothing to do.
    return json({ ok: true, ignored: 'no message_id in payload' });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // All ingest logic is shared with the reconcile poller — see _shared/email/ingest-gmail.ts.
  const result = await ingestGmailMessage(supabase, {
    messageId,
    threadId,
    connectedAccountId,
    historyId,
    source: 'composio-webhook',
  });

  return json(result);
});

