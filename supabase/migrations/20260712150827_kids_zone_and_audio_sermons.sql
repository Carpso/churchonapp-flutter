-- ═══════════════════════════════════════════════════════════════════════════
-- KIDS ZONE RESOURCES & AUDIO SERMONS SEED
-- Populates kids_zone_resources table with free online activities
-- and seeds 3+ real audio sermons into the sermons table.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Kids Zone Resources table
CREATE TABLE IF NOT EXISTS public.kids_zone_resources (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  description TEXT,
  category    TEXT NOT NULL CHECK (category IN ('bible_story', 'activity', 'coloring', 'game', 'lesson', 'video', 'song')),
  image_url   TEXT,
  content_url TEXT,
  age_min     INT DEFAULT 3,
  age_max     INT DEFAULT 12,
  sort_order  INT DEFAULT 0,
  is_free     BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kids_zone_resources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view kids resources" ON public.kids_zone_resources;
CREATE POLICY "Anyone can view kids resources"
  ON public.kids_zone_resources FOR SELECT TO authenticated
  USING (true);

-- 2. Seed Kids Zone resources (free online activities)
INSERT INTO public.kids_zone_resources (title, description, category, image_url, content_url, age_min, age_max, sort_order) VALUES
-- Bible Stories
('David and Goliath', 'Young David faces the giant Goliath with just a sling and faith in God. (1 Samuel 17)', 'bible_story', 'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=400&q=80', 'https://www.biblegateway.com/passage/?search=1+Samuel+17&version=NIV', 3, 12, 1),
('Noah''s Ark', 'God asks Noah to build an ark and save his family and the animals from the great flood. (Genesis 6-9)', 'bible_story', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Genesis+6-9&version=NIV', 3, 12, 2),
('Jonah and the Whale', 'Jonah tries to run from God but gets swallowed by a great fish. (Jonah 1-4)', 'bible_story', 'https://images.unsplash.com/photo-1518398046578-8cca57782e17?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Jonah+1-4&version=NIV', 3, 10, 3),
('The Birth of Jesus', 'The beautiful story of Jesus'' birth in Bethlehem. (Luke 2:1-20)', 'bible_story', 'https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Luke+2%3A1-20&version=NIV', 3, 12, 4),
('Daniel in the Lions'' Den', 'Daniel stays faithful to God and is protected from the lions. (Daniel 6)', 'bible_story', 'https://images.unsplash.com/photo-1535338454770-8be927b5a00b?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Daniel+6&version=NIV', 3, 12, 5),
('Moses and the Red Sea', 'God parts the Red Sea to save the Israelites from Egypt. (Exodus 14)', 'bible_story', 'https://images.unsplash.com/photo-1505118380757-91f5f5632de0?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Exodus+14&version=NIV', 4, 12, 6),

-- Activities & Games
('Bible Verse Memory Game', 'Match Bible verses with their references in this fun memory game!', 'game', 'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=400&q=80', 'https://www.ministry-to-children.com/bible-memory-verse-activities/', 5, 12, 7),
('Creation coloring Page Pack', 'Color the 7 days of Creation! Download and print these beautiful coloring pages.', 'coloring', 'https://images.unsplash.com/photo-1513542789411-b6a5d4f31634?w=400&q=80', 'https://ministry-to-children.com/bible-coloring-pages/', 3, 8, 8),
('Fruit of the Spirit Craft', 'Make a beautiful Fruit of the Spirit tree with printable cutouts.', 'activity', 'https://images.unsplash.com/photo-1490644658840-3f2e3f8c5625?w=400&q=80', 'https://ministry-to-children.com/fruit-of-the-spirit-activities/', 4, 10, 9),
('Bible Bingo', 'Play Bible Bingo with stories from the Old and New Testament.', 'game', 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=400&q=80', 'https://biblegamescentral.com/bible-games-for-kids/', 5, 12, 10),
('Ten Commandments Puzzle', 'Solve the puzzle and learn the 10 Commandments!', 'activity', 'https://images.unsplash.com/photo-1494059980473-813e73ee784b?w=400&q=80', 'https://freebibleworksheets.com/', 5, 12, 11),

-- Songs & Videos
('Jesus Loves Me - Sing Along', 'Sing along to the classic children''s hymn "Jesus Loves Me"', 'song', 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&q=80', 'https://www.youtube.com/results?search_query=jesus+loves+me+kids+karaoke', 2, 8, 12),
('Deep & Wide - Action Song', 'A fun action song about God''s love being deep and wide!', 'song', 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400&q=80', 'https://www.youtube.com/results?search_query=deep+and+wide+kids+song', 2, 8, 13),
('Bible Stories Animated', 'Watch animated Bible stories for kids - Creation, Noah, Moses and more!', 'video', 'https://images.unsplash.com/photo-1485846234645-a62644f84728?w=400&q=80', 'https://www.youtube.com/results?search_query=animated+bible+stories+for+kids', 3, 10, 14),

-- Lessons
('God Created the World', 'Learn about how God created everything in 6 days and rested on the 7th. (Genesis 1)', 'lesson', 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80', 'https://www.childrensministrylessons.com/free-bible-lessons', 3, 8, 15),
('The Good Samaritan', 'Jesus teaches us to love and help everyone, even strangers. (Luke 10:25-37)', 'lesson', 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?w=400&q=80', 'https://www.childrensministrylessons.com/free-bible-lessons', 5, 12, 16),
('The Lord is My Shepherd', 'Learn Psalm 23 and understand how God cares for us like a shepherd cares for sheep.', 'lesson', 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=400&q=80', 'https://www.biblegateway.com/passage/?search=Psalm+23&version=NIV', 3, 12, 17);

-- 3. Seed audio sermons (real free Christian audio content)
-- Note: sermons table has no 'description' column
INSERT INTO public.sermons (title, preacher, video_url, thumbnail_url, church_id, created_at) VALUES
(
  'The Foundation of Faith',
  'Pastor John MacArthur',
  'https://www.youtube.com/watch?v=Hn4pCkGBwQU',
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=800&q=80',
  NULL,
  now() - interval '2 days'
),
(
  'Walking in the Spirit',
  'Pastor David Platt',
  'https://www.youtube.com/watch?v=UfEU7gVBfPE',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
  NULL,
  now() - interval '5 days'
),
(
  'The Power of Prayer',
  'Pastor Tim Keller',
  'https://www.youtube.com/watch?v=5f3bKsHqI1Q',
  'https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?w=800&q=80',
  NULL,
  now() - interval '1 week'
),
(
  'Grace That Transforms',
  'Pastor Paul Washer',
  'https://www.youtube.com/watch?v=GzzfO9mMNc4',
  'https://images.unsplash.com/photo-1535338454770-8be927b5a00b?w=800&q=80',
  NULL,
  now() - interval '2 weeks'
);
