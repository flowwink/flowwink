-- Transparency sweep #97, finding A1: the generation backend has disclosed its
-- grounding sources (knowledge recycling) since day one, but the client threw
-- them away — no surface could show which published sources shaped a campaign.
-- Persist them on the proposal row so the disclosure survives a reload;
-- shape: [{ title, source }] straight from loadPublicKnowledgeBlock.
ALTER TABLE public.content_proposals
  ADD COLUMN IF NOT EXISTS grounding_sources jsonb;

COMMENT ON COLUMN public.content_proposals.grounding_sources IS
  'Published knowledge that grounded this proposal ([{title, source}]). Disclosure, not config — an admin cannot change what they cannot see.';
