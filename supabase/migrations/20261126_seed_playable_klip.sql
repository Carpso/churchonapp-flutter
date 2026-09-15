-- Seed one PUBLIC sample Klip that is genuinely PLAYABLE, so anyone can see
-- how the Klips feature looks and behaves (and demo it).
--
-- The existing samples pointed at `media.churchonapp.com/klips/…` objects that
-- may not exist, and at `assets.mixkit.co` (now 403) — so nothing played.

INSERT INTO public.klips
  (title, description, video_url, thumbnail_url, speaker, church_name,
   views, likes, amen_count, share_count, duration)
SELECT
  'Sunday Worship — Sample Klip',
  'Sample Klip so you can see how Klips look and play in the app.',
  'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
  'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800',
  'Church On App',
  'Church On App',
  0, 0, 0, 0, 10
WHERE NOT EXISTS (
  SELECT 1 FROM public.klips WHERE title = 'Sunday Worship — Sample Klip'
);
