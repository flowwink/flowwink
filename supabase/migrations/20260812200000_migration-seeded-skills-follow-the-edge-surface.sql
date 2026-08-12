-- Migration-seeded skills follow the edge surface they actually call.
--
-- A handful of skills are seeded directly by migrations (no code seed), which
-- means `sync:skills`/bootstrap NEVER touches them — they freeze at whatever
-- the migration wrote, including their handler. When the edge-surface refactor
-- collapsed `send-webinar-reminders` into the comms cluster (`comms-send`),
-- the live fleet's rows were repointed BY HAND (task #61)… and the migration
-- kept seeding the old handler. Every fresh install was therefore born with a
-- skill pointing at an edge function that does not exist — found by the skill
-- linter on the new sandbox (2026-08-12), the first from-zero install since
-- the refactor.
--
-- Hand-fixes on live instances don't reach the next instance; only the repo
-- does. Idempotent: repoints only rows still carrying the retired handler, so
-- the already-corrected fleet is untouched.

UPDATE public.agent_skills
   SET handler = 'edge:comms-send'
 WHERE name = 'send_webinar_reminders'
   AND handler = 'edge:send-webinar-reminders';
