-- Seed sample Klips so the Klips feature has content to react to.
-- Uses Creative Commons / public domain sermon video sources (user_id NULL,
-- treated as platform seed content).
INSERT INTO public.klips (
  user_id, user_name, title, description, video_url, thumbnail_url,
  speaker, church_name, views, likes, amen_count, comments_count, share_count, duration, tenant_id, church_id
)
SELECT
  NULL,
  'Church On App',
  v.title,
  v.description,
  v.video_url,
  v.thumbnail_url,
  v.speaker,
  'Church On App',
  v.views,
  v.likes,
  v.amen_count,
  v.comments_count,
  v.share_count,
  v.duration,
  NULL,
  NULL
FROM (VALUES
  (
    'The Good Samaritan - Animated Bible Story',
    'The parable of the Good Samaritan told as a short animated clip.',
    'https://media.churchonapp.com/klips/good_samaritan.mp4',
    'https://media.churchonapp.com/klips/good_samaritan.jpg',
    'Church On App', 1200, 85, 60, 12, 40, 180
  ),
  (
    'Psalm 23 - The Lord is My Shepherd',
    'A calming reading of Psalm 23 over peaceful imagery.',
    'https://media.churchonapp.com/klips/psalm23.mp4',
    'https://media.churchonapp.com/klips/psalm23.jpg',
    'Church On App', 2100, 160, 120, 25, 70, 240
  ),
  (
    'How to Study Your Bible Daily',
    'A quick practical guide to daily Bible reading and reflection.',
    'https://media.churchonapp.com/klips/bible_study_tip.mp4',
    'https://media.churchonapp.com/klips/bible_study_tip.jpg',
    'Church On App', 3400, 210, 150, 40, 95, 150
  )
) AS v(title, description, video_url, thumbnail_url, speaker, views, likes, amen_count, comments_count, share_count, duration)
WHERE NOT EXISTS (SELECT 1 FROM public.klips);
