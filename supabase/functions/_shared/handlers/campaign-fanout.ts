// approve_content_campaign — the fan-out that makes Campaigns real.
//
// Campaigns (Content Hub) is the authoring surface: ONE message, AI-drafted
// per-channel variants, a featured image with per-channel overrides, a
// schedule. Until now Approve only stamped status='approved' — nothing
// happened. social_posts.campaign_id existed in the schema but was never set:
// the seam was designed and never built.
//
// Approve IS the decision; the channel rails are the execution:
//   linkedin/twitter/instagram/facebook → social_posts rows (campaign_id set,
//     image inherited, scheduled if the campaign has a time — the 15-minute
//     sweep publishes via Composio)
//   blog        → blog_posts draft (body → minimal Tiptap doc)
//   newsletter  → newsletters draft
//   print       → reported as skipped (no rail)
//
// Same shape as propose→approve→voucher in accounting and quote→contract in
// sales: the approval materializes artifacts on rails that already know how
// to deliver them. Idempotent: re-approving an approved campaign returns the
// existing materialization instead of duplicating it.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type { HandlerCtx } from './qualify-lead.ts';

interface Materialized {
  channel: string;
  id: string;
  status: string;
}

const CHANNEL_TO_SOCIAL: Record<string, string> = {
  linkedin: 'linkedin',
  twitter: 'x',
  instagram: 'instagram',
  facebook: 'facebook',
};

function slugify(title: string): string {
  return title.toLowerCase().trim()
    .replace(/[åä]/g, 'a').replace(/ö/g, 'o')
    .replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-')
    .slice(0, 80);
}

/** Plain text/markdown-ish body → minimal Tiptap doc (paragraph per blank-line block). */
function textToTiptap(body: string): Record<string, unknown> {
  const paragraphs = String(body ?? '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  return {
    type: 'doc',
    content: paragraphs.length
      ? paragraphs.map((p) => ({ type: 'paragraph', content: [{ type: 'text', text: p }] }))
      : [{ type: 'paragraph' }],
  };
}

export async function executeApproveCampaign(
  supabase: SupabaseClient,
  args: Record<string, unknown>,
  ctx: HandlerCtx,
): Promise<Record<string, unknown>> {
  const proposalId = (args.proposal_id ?? args.id) as string | undefined;
  if (!proposalId) return { success: false, error: 'proposal_id is required' };

  const { data: proposal, error } = await supabase
    .from('content_proposals')
    .select('*')
    .eq('id', proposalId)
    .maybeSingle();
  if (error) return { success: false, error: `Load failed: ${error.message}` };
  if (!proposal) return { success: false, error: `Proposal ${proposalId} not found` };

  // Idempotency: an approved campaign returns what it already materialized.
  if (proposal.status === 'approved' || proposal.status === 'published') {
    const { data: existing } = await supabase
      .from('social_posts')
      .select('id, channel, status')
      .eq('campaign_id', proposalId);
    return {
      success: true,
      already_approved: true,
      proposal_id: proposalId,
      materialized: (existing ?? []).map((p) => ({ channel: p.channel, id: p.id, status: p.status })),
      note: 'Campaign was already approved — existing artifacts returned, nothing duplicated.',
    };
  }

  const variants = (proposal.channel_variants ?? {}) as Record<string, any>;
  const scheduledFor: string | null = (args.scheduled_for as string) ?? proposal.scheduled_for ?? null;
  const materialized: Materialized[] = [];
  const skipped: Array<{ channel: string; reason: string }> = [];

  const imageFor = (channel: string): string | null =>
    variants[channel]?.image_override || proposal.featured_image || null;

  // ── Social channels → social_posts (the sweep publishes) ──────────────
  for (const [variantKey, socialChannel] of Object.entries(CHANNEL_TO_SOCIAL)) {
    const v = variants[variantKey];
    if (!v) continue;
    const text: string = v.text ?? v.caption ?? '';
    if (!text.trim()) { skipped.push({ channel: variantKey, reason: 'empty variant text' }); continue; }
    const hashtags: string[] = Array.isArray(v.hashtags) ? v.hashtags : [];
    const content = hashtags.length
      ? `${text}\n\n${hashtags.map((h: string) => (h.startsWith('#') ? h : `#${h}`)).join(' ')}`
      : text;

    const { data: post, error: postErr } = await supabase
      .from('social_posts')
      .insert({
        channel: socialChannel,
        content,
        media_url: imageFor(variantKey),
        campaign_id: proposalId,
        scheduled_at: scheduledFor,
        status: scheduledFor ? 'scheduled' : 'draft',
        created_by: ctx.callerUserId ?? null,
      })
      .select('id, status')
      .single();
    if (postErr) { skipped.push({ channel: variantKey, reason: postErr.message }); continue; }
    materialized.push({ channel: variantKey, id: post.id, status: post.status });
  }

  // ── Blog → blog_posts draft ───────────────────────────────────────────
  if (variants.blog?.title) {
    const b = variants.blog;
    let slug = slugify(b.title);
    const { data: slugTaken } = await supabase
      .from('blog_posts').select('id').eq('slug', slug).maybeSingle();
    if (slugTaken) slug = `${slug}-${proposalId.slice(0, 6)}`;

    const { data: post, error: blogErr } = await supabase
      .from('blog_posts')
      .insert({
        slug,
        title: b.title,
        excerpt: b.excerpt ?? null,
        content_json: textToTiptap(b.body ?? ''),
        featured_image: imageFor('blog'),
        status: 'draft',
        meta_json: Array.isArray(b.seo_keywords) && b.seo_keywords.length
          ? { keywords: b.seo_keywords }
          : {},
        created_by: ctx.callerUserId ?? null,
      })
      .select('id, status')
      .single();
    if (blogErr) skipped.push({ channel: 'blog', reason: blogErr.message });
    else materialized.push({ channel: 'blog', id: post.id, status: post.status });
  }

  // ── Newsletter → newsletters draft ────────────────────────────────────
  if (variants.newsletter?.subject) {
    const n = variants.newsletter;
    const { data: nl, error: nlErr } = await supabase
      .from('newsletters')
      .insert({
        subject: n.subject,
        content_json: Array.isArray(n.blocks) ? { blocks: n.blocks, preview_text: n.preview_text ?? null } : { preview_text: n.preview_text ?? null },
        status: 'draft',
        created_by: ctx.callerUserId ?? null,
      })
      .select('id, status')
      .single();
    if (nlErr) skipped.push({ channel: 'newsletter', reason: nlErr.message });
    else materialized.push({ channel: 'newsletter', id: nl.id, status: nl.status });
  }

  if (variants.print) skipped.push({ channel: 'print', reason: 'no delivery rail — export manually' });

  // ── Stamp the decision ────────────────────────────────────────────────
  const { error: upErr } = await supabase
    .from('content_proposals')
    .update({
      status: 'approved',
      approved_by: ctx.callerUserId ?? null,
      approved_at: new Date().toISOString(),
    })
    .eq('id', proposalId);
  if (upErr) {
    return {
      success: false,
      error: `Artifacts created but approval stamp failed: ${upErr.message}`,
      materialized,
      skipped,
    };
  }

  return {
    success: true,
    proposal_id: proposalId,
    materialized,
    skipped,
    note: scheduledFor
      ? `Social posts scheduled for ${scheduledFor} — the sweep publishes them.`
      : 'Social posts created as drafts (campaign has no schedule) — set them scheduled in Social Posts when ready.',
  };
}
