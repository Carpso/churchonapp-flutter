-- ═══════════════════════════════════════════════════════════════════════════════
-- KIDS ZONE: FIX "Noah and the Ark" WRONG AUDIO STORY
-- The story previously pointed at bible_001.mp3 (KJV 2001 "Genesis Ch. 1-14"),
-- which starts at Creation — children heard the wrong story.
-- Now plays a dedicated Noah story (Genesis 6-9) self-hosted on R2.
-- ═══════════════════════════════════════════════════════════════════════════════

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/noah_and_the_ark.mp3'
WHERE title = 'Noah and the Ark';
