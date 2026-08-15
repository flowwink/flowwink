-- Learning mode: keep what the research found, and what the human chose.
--
-- Magnus (2026-08-14): "vi bör spara all knowledge vi får in på ett smart
-- sätt … vad sökte vi på, med vilka variabler, vilka briefs användaren väljer
-- mellan — idealet är att systemet lär sig av de val användarna gör, men utan
-- att vi spränger context windows."
--
-- Same shape as companies.web_raw: the expensive part is the FETCH, so keep it
-- with provenance. The new part is the CHOICE — which angle won, which were
-- rejected, which hooks were kept. That is the only signal that says something
-- about this company's taste rather than the model's priors, and it is what a
-- later preference distillate (a few hundred characters, injected like the
-- identity block) will be built from. Raw history never enters a prompt.

ALTER TABLE public.content_research
  -- The exact brief that produced this research — "what did we search for,
  -- with which variables". Without it a saved research is an answer with no
  -- question.
  ADD COLUMN IF NOT EXISTS brief jsonb,
  -- The human's verdict on it.
  ADD COLUMN IF NOT EXISTS chosen_angle text,
  ADD COLUMN IF NOT EXISTS chosen_hooks text[],
  ADD COLUMN IF NOT EXISTS rejected_angles text[],
  ADD COLUMN IF NOT EXISTS chosen_at timestamptz;

COMMENT ON COLUMN public.content_research.brief IS
  'The generation brief as submitted (topic, audience, industry, channels, tone, goals) — provenance for the research beside it.';
COMMENT ON COLUMN public.content_research.chosen_angle IS
  'Which angle the human picked. With rejected_angles this is the preference signal learning mode distills — never the raw rows in a prompt.';

-- content_proposals.source_research (jsonb) existed from day one and was never
-- set, so no campaign could be traced back to the research that shaped it. It
-- now carries { research_id, topic, chosen_angle }; index the id so "show me
-- everything that came out of this research" is one query.
CREATE INDEX IF NOT EXISTS idx_content_proposals_source_research_id
  ON public.content_proposals ((source_research->>'research_id'))
  WHERE source_research IS NOT NULL;
