// contract_email — email the customer the signing link for a contract.
//
// The gap this fills: the admin "Send for signature" button only copied the
// link to the clipboard — no mail ever went out. Quotes had an email path;
// contracts did not, so a signing request could only be sent by hand-pasting
// the URL. This mirrors quote_email: a FRAGMENT (email-send wraps it in the
// operator's branded shell) routed through the provider-agnostic router with
// expects_reply, since a signing request is a conversation the customer may
// reply to.
import { getServiceClient } from '../_shared/supabase-clients.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface Body {
  contract_id?: string;
  public_url?: string;
  reminder?: boolean;
  custom_message?: string;
}

const escapeHtml = (s: string) =>
  String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

// deno-lint-ignore no-explicit-any
async function primaryHex(supabase: any): Promise<string> {
  const { data } = await supabase.from('site_settings').select('value').eq('key', 'branding').maybeSingle();
  const triplet = (data?.value as { primaryColor?: string } | null)?.primaryColor;
  // HSL triplet "H S% L%" → hex; the shell does the same, kept local to avoid a
  // cross-import here.
  const m = String(triplet ?? '').match(/^(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)%$/);
  if (!m) return /^#[0-9a-fA-F]{6}$/.test(String(triplet ?? '')) ? String(triplet) : '#1f6feb';
  const h = +m[1] / 360, s = +m[2] / 100, l = +m[3] / 100;
  const k = (n: number) => (n + h * 12) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  const to = (v: number) => Math.round(v * 255).toString(16).padStart(2, '0');
  return `#${to(f(0))}${to(f(8))}${to(f(4))}`;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    const supabase = getServiceClient();
    const body: Body = await req.json();
    if (!body.contract_id || !body.public_url) {
      return json({ error: 'contract_id and public_url required' }, 400);
    }

    const { data: contract, error: cErr } = await supabase
      .from('contracts')
      .select('id, title, contract_number, counterparty_name, counterparty_email')
      .eq('id', body.contract_id)
      .single();
    if (cErr || !contract) throw new Error(cErr?.message || 'Contract not found');
    if (!contract.counterparty_email) throw new Error('Contract has no counterparty_email');

    const { data: settings } = await supabase
      .from('site_settings').select('value').eq('key', 'general').maybeSingle();
    // deno-lint-ignore no-explicit-any
    const siteName = (settings?.value as any)?.site_name || 'FlowWink';
    const hex = await primaryHex(supabase);

    const intro = body.reminder
      ? 'A reminder to review and sign the agreement below.'
      : 'Please review and sign the agreement below.';
    const custom = body.custom_message
      ? `<p style="white-space:pre-wrap">${escapeHtml(body.custom_message)}</p>` : '';

    // Fragment — email-send applies the branded shell.
    const html = `
      <h2 style="margin:0 0 12px;font-size:20px;">${escapeHtml(contract.title || 'Agreement')}</h2>
      <p>${intro}</p>
      ${custom}
      <div style="background:#f9fafb;border:1px solid #e6e8ec;border-radius:8px;padding:12px 16px;margin:16px 0;font-size:14px;">
        <div><span style="color:#6b7280">Agreement</span> &nbsp; <strong>${escapeHtml(contract.contract_number || '')}</strong></div>
      </div>
      <p style="margin:24px 0;">
        <a href="${body.public_url}" style="display:inline-block;padding:12px 24px;background-color:${hex};color:#ffffff;text-decoration:none;border-radius:6px;font-weight:600;">Review &amp; sign</a>
      </p>
      <p style="font-size:12px;color:#6b7280;word-break:break-all">Or open this link:<br/>${escapeHtml(body.public_url)}</p>
    `;

    const subject = body.reminder
      ? `Reminder: sign ${contract.contract_number} from ${siteName}`
      : `Agreement ${contract.contract_number} from ${siteName} — ready to sign`;

    // expects_reply: a signing request is a conversation, not a receipt — same
    // reasoning as quote_email (Composio → SMTP → Resend).
    const { data: sendData, error: sendErr } = await supabase.functions.invoke('email-send', {
      body: {
        to: contract.counterparty_email,
        subject,
        html,
        expects_reply: true,
        source: 'contract_email',
        tags: { kind: body.reminder ? 'contract_reminder' : 'contract', contract_id: contract.id },
      },
    });
    if (sendErr) throw new Error(sendErr.message || 'email-send failed');
    if (!sendData?.success) throw new Error(sendData?.error || 'email-send returned failure');

    return json({ success: true, simulated: !!sendData?.simulated, to: contract.counterparty_email });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
}
