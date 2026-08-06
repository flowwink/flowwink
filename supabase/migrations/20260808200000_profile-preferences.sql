-- User preferences move into the database — "persistent per user" was
-- localStorage keyed by userId, which is persistent per BROWSER PER ORIGIN.
-- The day the instance got its real domain, every user's pinned pages
-- vanished: new origin, empty storage. Preferences that claim to follow the
-- user must live where the user lives.
--
-- One jsonb column instead of a table-per-preference: pins today, whatever a
-- user-level setting needs tomorrow, namespaced by key inside the object.
-- RLS already restricts UPDATE to the profile's owner.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferences jsonb NOT NULL DEFAULT '{}'::jsonb;
