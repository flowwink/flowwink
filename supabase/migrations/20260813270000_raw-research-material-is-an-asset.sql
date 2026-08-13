-- The raw research material is an asset, not exhaust.
--
-- Research and enrich scrape the prospect's website (a paid Firecrawl/Jina
-- read), distill it, and used to throw the raw text away — keeping only the
-- distillation in web_summary. That was backwards in the other direction:
-- the raw material enables free re-distillation when the prompt or the ICP
-- improves, deeper AI-compose personalization (details the distillation
-- dropped), and future breadth search in FlowWork ("what do we know about
-- Svalner?") via the Knowledge Index rails.
--
-- Shape: { url, fetched_at, provider?, content, search_snippets[] }.
-- Provenance is mandatory in spirit: content without its read-date becomes a
-- future lie — sites change. Refreshed on every research/enrich run (this is
-- reading, not master data). Deliberately NOT fed into fit prompts wholesale;
-- web_summary stays the working set, web_raw is the archive.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS web_raw jsonb;

COMMENT ON COLUMN public.companies.web_raw IS
  'Raw scraped material from research/enrich: { url, fetched_at, provider, content, search_snippets }. Archive for re-distillation and breadth search; web_summary is the distilled working set.';
