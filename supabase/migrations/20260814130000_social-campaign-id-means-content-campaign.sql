-- social_posts.campaign_id means CONTENT campaign — the name-collision class.
--
-- The column carried an FK to ad_campaigns (the ads system) since birth and
-- was never written by anything. When the campaign fan-out started setting it
-- to the content_proposals id, the FK rejected every insert: the linkedin
-- variant of Magnus's first real campaign silently skipped with an FK
-- violation in a toast that vanished. Blog and newsletter landed; the channel
-- the whole rail was built for did not.
--
-- Repoint to content_proposals. ON DELETE SET NULL: a deleted campaign must
-- not take published posts' history with it.

ALTER TABLE public.social_posts
  DROP CONSTRAINT IF EXISTS social_posts_campaign_id_fkey;

ALTER TABLE public.social_posts
  ADD CONSTRAINT social_posts_campaign_id_fkey
  FOREIGN KEY (campaign_id) REFERENCES public.content_proposals(id) ON DELETE SET NULL;
