-- Replace the fake placeholder sermons with REAL UPCI (United Pentecostal
-- Church International) sermon videos as the global sample set.
--
-- Every YouTube id below was verified embeddable via the YouTube oEmbed
-- endpoint (HTTP 200). These are global samples (tenant_id / church_id NULL)
-- so they populate the "Latest Sermon" card and Sermons tab for every user
-- until a tenant publishes its own sermons.

-- 1) Remove the old placeholder samples (dead sample-bucket / soundhelix URLs).
DELETE FROM public.sermons
 WHERE video_url LIKE '%test-videos.co.uk%'
    OR video_url LIKE '%flutter.github.io/assets-for-api-docs%'
    OR video_url LIKE '%media.w3.org%'
    OR video_url LIKE '%soundhelix.com%';

-- 2) Seed the UPCI samples.
INSERT INTO public.sermons
  (title, preacher, speaker, video_url, thumbnail_url, category, is_live, viewer_count, duration_minutes, created_at)
VALUES
  ('Global Missions Service', 'UPCI General Conference', 'UPCI General Conference',
   'https://www.youtube.com/watch?v=dO5ksn0_W4Y', 'https://i.ytimg.com/vi/dO5ksn0_W4Y/hqdefault.jpg',
   'Apostolic Teaching', false, 0, 150, now() - interval '1 day'),
  ('Holiness', 'Raymond Woodward', 'Raymond Woodward',
   'https://www.youtube.com/watch?v=la0-cCaUlCw', 'https://i.ytimg.com/vi/la0-cCaUlCw/hqdefault.jpg',
   'Apostolic Teaching', false, 0, 29, now() - interval '2 day'),
  ('North American Missions Service', 'J. Todd Nichols', 'J. Todd Nichols',
   'https://www.youtube.com/watch?v=McYG9kOZ5VQ', 'https://i.ytimg.com/vi/McYG9kOZ5VQ/hqdefault.jpg',
   'Missions', false, 0, 154, now() - interval '3 day'),
  ('Consumed by Zeal', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=nsfIY84xT-s', 'https://i.ytimg.com/vi/nsfIY84xT-s/hqdefault.jpg',
   'Apostolic Teaching', false, 0, 62, now() - interval '4 day'),
  ('A Call to Humility', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=YexcyAwJaU8', 'https://i.ytimg.com/vi/YexcyAwJaU8/hqdefault.jpg',
   'Apostolic Teaching', false, 0, 55, now() - interval '5 day'),
  ('General Superintendent''s Service', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=o0i8-S5MTvA', 'https://i.ytimg.com/vi/o0i8-S5MTvA/hqdefault.jpg',
   'Apostolic Teaching', false, 0, 90, now() - interval '6 day'),
  ('2026 State of the Church Address', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=h280XINsVDE', 'https://i.ytimg.com/vi/h280XINsVDE/hqdefault.jpg',
   'Church News', false, 0, 40, now() - interval '7 day'),
  ('One True God', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=WRvR52X3Qg8', 'https://i.ytimg.com/vi/WRvR52X3Qg8/hqdefault.jpg',
   'Bible Study', false, 0, 45, now() - interval '8 day'),
  ('Is Mental Health Treatment Compatible with Christian Faith?', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=lKZoFpJe4lY', 'https://i.ytimg.com/vi/lKZoFpJe4lY/hqdefault.jpg',
   'Bible Study', false, 0, 35, now() - interval '9 day'),
  ('Rev. J.P. Story and Rev. Mark Drost', 'Texas District UPCI', 'Texas District UPCI',
   'https://www.youtube.com/watch?v=Ud-PfZo2Ms4', 'https://i.ytimg.com/vi/Ud-PfZo2Ms4/hqdefault.jpg',
   'Camp Meeting', false, 0, 126, now() - interval '10 day'),
  ('Freedom to Celebrate Christmas', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=G-YS3rYXx7s', 'https://i.ytimg.com/vi/G-YS3rYXx7s/hqdefault.jpg',
   'Bible Study', false, 0, 2, now() - interval '11 day'),
  ('It''s Okay to Seek Help', 'David K. Bernard', 'David K. Bernard',
   'https://www.youtube.com/watch?v=kxMCHmNQQRY', 'https://i.ytimg.com/vi/kxMCHmNQQRY/hqdefault.jpg',
   'Bible Study', false, 0, 1, now() - interval '12 day');
