-- 20260899: Sample sermon clips for testing player and livestream
-- Uses publicly available Christian media from archive.org and other free sources
-- Note: sermons table has no 'description' column

INSERT INTO public.sermons (title, preacher, video_url, thumbnail_url, is_live, viewer_count, church_id, created_at) VALUES
(
  'The Foundation of Faith - Live Test Stream',
  'Pastor John MacArthur',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=800&q=80',
  true,
  42,
  NULL,
  now() - interval '1 hour'
),
(
  'Walking in the Spirit - Audio Sermon',
  'Pastor David Platt',
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
  false,
  0,
  NULL,
  now() - interval '2 days'
),
(
  'The Power of Prayer - Video Sermon',
  'Pastor Tim Keller',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
  'https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?w=800&q=80',
  false,
  0,
  NULL,
  now() - interval '1 week'
),
(
  'Grace That Transforms - Live Replay',
  'Pastor Paul Washer',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  'https://images.unsplash.com/photo-1535338454770-8be927b5a00b?w=800&q=80',
  false,
  0,
  NULL,
  now() - interval '2 weeks'
),
(
  'Faith in Action - Sunday Service',
  'Pastor Charles Stanley',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
  false,
  0,
  NULL,
  now() - interval '3 weeks'
),
(
  'The Living Word - Bible Study',
  'Pastor Chuck Swindoll',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
  'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=800&q=80',
  false,
  0,
  NULL,
  now() - interval '1 month'
);

-- Also add a scheduled upcoming live stream for testing the live indicator
INSERT INTO public.sermons (title, preacher, video_url, thumbnail_url, is_live, viewer_count, church_id, created_at) VALUES
(
  'Upcoming Live: The Hope of Glory',
  'Pastor John Piper',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
  false,
  0,
  NULL,
  now() + interval '30 minutes'
);