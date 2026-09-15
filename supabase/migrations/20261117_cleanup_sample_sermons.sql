-- Sample-sermon cleanup.
--
-- Audit of the seeded `sermons` table found:
--   * 64 duplicate rows — 4 titles each repeated 17x with identical URLs.
--   * 70 rows pointing at YouTube ids that DO NOT EXIST (404 via oEmbed) —
--     so even after adding in-app YouTube playback, those sermons could
--     never play.
--   * 2 rows pointing at the "rickroll" placeholder video (dQw4w9WgXcQ).
--   * 8 rows that are genuinely playable Google/sample-bucket MP4s + 1 MP3.
--
-- This migration keeps one row per title and repoints every dead URL at a
-- real, playable sample MP4 so the sermon list and player work end to end.
-- A full pre-cleanup snapshot is kept in `_backup_sample_sermon_cleanup`.

CREATE TABLE IF NOT EXISTS public._backup_sample_sermon_cleanup AS
SELECT * FROM public.sermons;

-- 1) Drop exact duplicates (same title AND same video_url), keep the earliest.
DELETE FROM public.sermons s
USING public.sermons k
WHERE s.title = k.title
  AND COALESCE(s.video_url, '') = COALESCE(k.video_url, '')
  AND (
    s.created_at > k.created_at
    OR (s.created_at = k.created_at AND s.id > k.id)
  );

-- 2) Repoint non-existent YouTube ids + the rickroll placeholder at playable
--    sample videos. NOTE: the legacy `commondatastorage.googleapis.com/
--    gtv-videos-bucket` bucket now returns 403 (it is no longer public), so we
--    use hosts verified reachable with a ranged GET (206 video/mp4):
--    test-videos.co.uk and the Flutter assets CDN.
UPDATE public.sermons
   SET video_url = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4'
 WHERE video_url LIKE '%GzzfO9mMNc4%';

UPDATE public.sermons
   SET video_url = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4'
 WHERE video_url LIKE '%Hn4pCkGBwQU%';

UPDATE public.sermons
   SET video_url = 'https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_1MB.mp4'
 WHERE video_url LIKE '%5f3bKsHqI1Q%';

UPDATE public.sermons
   SET video_url = 'https://test-videos.co.uk/vids/sintel/mp4/h264/360/Sintel_360_10s_1MB.mp4'
 WHERE video_url LIKE '%UfEU7gVBfPE%';

UPDATE public.sermons
   SET video_url = 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4'
 WHERE video_url LIKE '%dQw4w9WgXcQ%';

-- 3) Repoint the remaining dead sample-bucket / mixkit URLs (403) at hosts
--    that are actually reachable today.
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/360/Jellyfish_360_10s_1MB.mp4'
 WHERE video_url LIKE '%ElephantsDream.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_1MB.mp4'
 WHERE video_url LIKE '%ForBiggerBlazes.mp4%';
UPDATE public.sermons SET video_url = 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4'
 WHERE video_url LIKE '%ForBiggerEscapes.mp4%';
UPDATE public.sermons SET video_url = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4'
 WHERE video_url LIKE '%ForBiggerFun.mp4%';
UPDATE public.sermons SET video_url = 'https://media.w3.org/2010/05/sintel/trailer.mp4'
 WHERE video_url LIKE '%BigBuckBunny.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/sintel/mp4/h264/360/Sintel_360_10s_1MB.mp4'
 WHERE video_url LIKE '%mixkit-pastor-preaching%';

-- 4) Mop up any remaining dead gtv-videos-bucket URLs (the previous run of
--    this migration had already rewritten the YouTube ids to that bucket).
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4'
 WHERE video_url LIKE '%ForBiggerJoyrides.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4'
 WHERE video_url LIKE '%ForBiggerMeltdowns.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4'
 WHERE video_url LIKE '%SubaruOutbackOnStreetAndDirt.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_1MB.mp4'
 WHERE video_url LIKE '%/sample/Sintel.mp4%';
UPDATE public.sermons SET video_url = 'https://test-videos.co.uk/vids/sintel/mp4/h264/360/Sintel_360_10s_1MB.mp4'
 WHERE video_url LIKE '%TearsOfSteel.mp4%';

-- 3) Collapse the two "Walking in the Spirit" rows (one was the rickroll
--    placeholder) down to the earliest, so every title is now unique.
DELETE FROM public.sermons s
USING public.sermons k
WHERE s.title = k.title
  AND s.created_at > k.created_at;
