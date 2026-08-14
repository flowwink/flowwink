// Knowledge recycling — outward content grounds in what the company has
// ALREADY published, retrieved per topic with the PUBLIC's eyes.
//
// The reasoning (Magnus + Claude, 2026-08-14): identity is small and always-on
// (business-identity-block); knowledge is large and only partly relevant, so
// it must be RETRIEVED per topic, not injected wholesale. And for outward
// writing the grounding has a confidentiality dimension: a LinkedIn post is
// maximally public, so only public sources may ground it verbatim.
//
// Both rules are enforced by construction here:
//  - per-topic: Retrieval Engine ranks chunks against the campaign topic
//  - public-only: retrieve() runs on an ANON-key client — "retrieval always
//    runs with the caller's eyes", and these eyes are a visitor's. RLS on
//    knowledge_chunks is the boundary; internal wiki/handbook/documents are
//    invisible to this client by the same mechanism that hides them on the
//    website. No allowlist to maintain, nothing to forget.
//
// Soft-fail (Law 4): no index, no anon key, or an RPC error → empty block,
// generation proceeds on identity + brief alone.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.87.1';
import { retrieve, renderContext } from '../retrieval/index.ts';

export interface PublicKnowledgeGrounding {
  block: string;
  sources: Array<{ title: string; source: string }>;
}

export async function loadPublicKnowledgeBlock(topic: string): Promise<PublicKnowledgeGrounding> {
  const empty: PublicKnowledgeGrounding = { block: '', sources: [] };
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !anonKey || !topic?.trim()) return empty;

    const publicEyes = createClient(url, anonKey);
    const chunks = await retrieve(publicEyes, { query: topic, k: 6, tokenBudget: 2500 });
    if (chunks.length === 0) return empty;

    return {
      block:
        `\n\n## Published knowledge on this topic (public sources — recycle freely)\n` +
        `This is what the company has already published about the topic. Stay factually ` +
        `consistent with it, reuse its terminology and claims, and never contradict it. ` +
        `Write natively — no citation markers in the output.\n\n` +
        renderContext(chunks),
      sources: chunks.map((c) => ({ title: c.title, source: c.sourceTable })),
    };
  } catch (e) {
    console.warn('[knowledge-recycling] retrieval skipped:', e instanceof Error ? e.message : e);
    return empty;
  }
}
