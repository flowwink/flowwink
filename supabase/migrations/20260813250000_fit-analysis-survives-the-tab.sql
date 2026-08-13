-- The fit analysis survives closing the tab.
--
-- Magnus, mid Svalner test run (2026-08-13): "Kommer analysen sparas om jag
-- stänger sidan?" — it did not. The score, the advice, the problem mapping and
-- the introduction letter lived only in React state; the aggregator run was
-- logged in agent_activity but the assessment itself evaporated. The Hunter
-- side already persists (leads.email_confidence / email_status /
-- email_provenance — the "where did you get my address / wrong person /
-- no longer works there" evidence). This closes the other half.
--
-- One CURRENT assessment per company, on the company row — same discipline as
-- "one number per thing": history is in agent_activity, the row carries the
-- latest. fit_analysis holds the full result (advice, problem_mapping,
-- email_subject, introduction_letter, decision_maker, ai_scored, analyzed_at).

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS fit_score integer,
  ADD COLUMN IF NOT EXISTS fit_analysis jsonb,
  ADD COLUMN IF NOT EXISTS fit_analyzed_at timestamptz;

COMMENT ON COLUMN public.companies.fit_analysis IS
  'Latest prospect fit assessment (FitAnalysisResult shape from Sales Intelligence). Superseded in place; run history lives in agent_activity.';
