/**
 * Retrieval Engine — the ONE named exception to caller's-eyes retrieval.
 *
 * `docs_pages` (FlowWink's own repo documentation) is classed 'internal' in
 * the index so that a customer's anon surface can never pull vendor docs out
 * of the customer's database via the generic search RPC (#214, 2026-08-12:
 * publishable key + sources:["docs_pages"] read 7,959 chunks across four
 * instances). That tier fix was correct — and it silently starved the one
 * surface that legitimately serves those docs to anonymous readers: the /docs
 * page's own chat (docs-chat), which retrieved with anon eyes and from
 * 2026-08-12 grounded on nothing, answering "not in the documentation" on
 * every instance (#95).
 *
 * The docs are public on GitHub; 'internal' is not a confidentiality claim
 * but an AUDIENCE-ROUTING one: vendor docs must not surface in customer-
 * facing generic search, only through the dedicated docs surface. This module
 * IS that routing: it retrieves with the service client (RLS bypass) but the
 * source list is pinned to docs_pages here, in code the caller cannot reach —
 * docs-chat's request body carries only `messages`. Nothing else may travel
 * through this door:
 *
 *   - the source pin is a module-local constant, not a parameter;
 *   - the options type has no `sources` field to widen;
 *   - guardrails (retrieval-engine.guardrails.test.ts) pin docs-chat to this
 *     helper and this helper to docs_pages, and forbid every other consumer
 *     from importing it.
 *
 * When #80 ships docs as a prebuilt artifact (chunks + embeddings in the
 * repo, out of customer DBs entirely) this module is the single call site to
 * repoint, then delete.
 */
/* eslint-disable @typescript-eslint/no-explicit-any -- Deno edge module; client type varies per caller */
import { retrieve, type RetrievedChunk } from './index.ts';

/** The pinned scope of this exception. Never widen; never parameterize. */
const VENDOR_DOCS_SOURCES = ['docs_pages'];

export interface VendorDocsQuery {
  query: string;
  k?: number;
  tokenBudget?: number;
  queryEmbedding?: number[] | null;
  // Deliberately NO `sources` field — the pin above is the whole point.
}

export async function retrieveVendorDocs(
  service: any,
  { query, k = 8, tokenBudget = 4000, queryEmbedding }: VendorDocsQuery,
): Promise<RetrievedChunk[]> {
  return retrieve(service, {
    query,
    k,
    tokenBudget,
    sources: VENDOR_DOCS_SOURCES,
    queryEmbedding,
  });
}
