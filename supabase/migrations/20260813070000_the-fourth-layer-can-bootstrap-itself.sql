-- The fourth layer can bootstrap itself.
--
-- sync_skills_from_code (in agent-execute) reconciles agent_skills against the
-- seed artifact bundled with every edge deploy — the missing "4th layer" of
-- the push-deploys-everything chain. But the skill rail resolves skills from
-- the agent_skills TABLE, so on an instance whose registry predates this skill
-- the reconciler could never be invoked to add itself: the tool that fixes
-- missing skills was a missing skill.
--
-- Migrations are the one channel that reaches every instance on every deploy,
-- so this seeds the single bootstrap row. Deliberately minimal: the first call
-- refreshes its own description/instructions/tool_definition from the bundled
-- artifact (it is in there too), so this SQL never needs to track the seed's
-- wording. Idempotent: inserts only when absent, never overwrites — an
-- operator's runtime changes to the row survive replays.

INSERT INTO public.agent_skills
  (name, description, category, handler, scope, tool_definition, enabled, mcp_exposed, origin, trust_level, requires_staging)
SELECT
  'sync_skills_from_code',
  'Reconcile this instance''s skill registry against the deployed code''s bundled seed artifact. Inserts missing skills, refreshes drifted definition fields, never touches trust_level. Use when: skills look stale or missing after a deploy.',
  'system',
  'internal:sync_skills_from_code',
  'internal',
  '{"type":"function","function":{"name":"sync_skills_from_code","description":"Reconcile agent_skills against the deploy''s bundled seed artifact — insert missing, refresh drifted, never touch trust_level. Idempotent; hash-gated.","parameters":{"type":"object","properties":{"force":{"type":"boolean","description":"Re-apply even when the artifact hash matches."}}}}}'::jsonb,
  true, true, 'bundled', 'auto', false
WHERE NOT EXISTS (
  SELECT 1 FROM public.agent_skills WHERE name = 'sync_skills_from_code'
);
