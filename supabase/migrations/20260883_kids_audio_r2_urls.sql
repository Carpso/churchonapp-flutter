-- ═══════════════════════════════════════════════════════════════════════════════
-- KIDS ZONE: REPLACE archive.org AUDIO WITH SELF-HOSTED R2 AUDIO
-- The 10 kids bible story resources originally pointed at
-- https://archive.org/download/kids_bible_stories_librivox/*.mp3 (dead).
-- Now stream from our own Cloudflare R2 bucket (media.churchonapp.com):
--   • DBSOT dramatized Old Testament stories (bible-audio/dbsot/dbsot_NN.mp3)
--   • KJV complete 2001 chapter-range files (bible-audio/kjv-dramatized/bible_NNN.mp3)
-- ═══════════════════════════════════════════════════════════════════════════════

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/dbsot/dbsot_13.mp3'
WHERE title = 'David and Goliath';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_001.mp3'
WHERE title = 'Noah and the Ark';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/dbsot/dbsot_19.mp3'
WHERE title = 'Jonah and the Big Fish';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_096.mp3'
WHERE title = 'The Birth of Jesus';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/dbsot/dbsot_04.mp3'
WHERE title = 'Joseph and His Brothers';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/dbsot/dbsot_07.mp3'
WHERE title = 'Moses and the Red Sea';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/dbsot/dbsot_20.mp3'
WHERE title = 'Daniel in the Lions Den';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_097.mp3'
WHERE title = 'The Good Samaritan';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_097.mp3'
WHERE title = 'The Prodigal Son';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_099.mp3'
WHERE title = 'Jesus Feeds 5000';
