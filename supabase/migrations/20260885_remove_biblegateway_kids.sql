-- Remove redundant external biblegateway.com kids bible-story links.
-- Self-hosted R2 versions for Noah, Jonah and Daniel are already present
-- in kids_zone_resources (added/migrated in 20260875 + 20260883).
DELETE FROM public.kids_zone_resources
WHERE category = 'bible_story'
  AND content_url LIKE '%biblegateway.com%';
