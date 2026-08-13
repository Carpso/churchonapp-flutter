-- Normalize "The Good Samaritan" back to bible_story category after dedup.
UPDATE public.kids_zone_resources
SET category = 'bible_story'
WHERE title = 'The Good Samaritan';
