-- Research keeps what it read.
--
-- prospect_research has scraped the prospect's website since day one — and
-- then threw the text away: it rode along in the response's _raw block, was
-- never persisted, and the fit analysis never saw it. That is why every fit
-- assessment said "lacks essential data such as industry and company size":
-- the module had READ the answer and kept no memory of it.
--
-- web_summary stores the scraped/distilled site content on the company row.
-- The fit aggregator selects the company row wholesale, so what research
-- learned now automatically reaches the scoring prompt — matching our ICP and
-- offering against what THEY do, which is the entire point of the module.
-- industry/size get filled by the research distillation step (AI, soft-fail)
-- into the columns that already existed.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS web_summary text;

COMMENT ON COLUMN public.companies.web_summary IS
  'What prospect research read on their website (scraped excerpt or AI distillation). Refreshed on each research run; grounds fit analysis and outreach.';
