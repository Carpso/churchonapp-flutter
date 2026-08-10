-- Kids Zone audio content from public-domain LibriVox (via Internet Archive).
-- Zero hosting cost — streamed directly. Move to R2 for caching later.
INSERT INTO public.kids_zone_resources (title, description, category, image_url, content_url, age_min, age_max, sort_order, is_free)
SELECT * FROM (VALUES
  ('David and Goliath'::text, 'The shepherd boy defeats the giant with faith and a sling. Audio story by LibriVox volunteers.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/david_goliath.mp3'::text, 3, 12, 10, true),
  ('Noah and the Ark'::text, 'God saves Noah, his family, and the animals from the great flood. Dramatized audio.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/noah_ark.mp3'::text, 3, 12, 20, true),
  ('Jonah and the Big Fish'::text, 'Jonah runs from God and gets swallowed by a great fish. Interactive audio story.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/jonah_whale.mp3'::text, 3, 12, 30, true),
  ('The Birth of Jesus'::text, 'The Christmas story — Mary, Joseph, shepherds, and the baby in the manger.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/birth_jesus.mp3'::text, 3, 12, 40, true),
  ('Joseph and His Brothers'::text, 'Sold into slavery, Joseph rises to save Egypt and forgives his family.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/joseph_brothers.mp3'::text, 6, 12, 50, true),
  ('Moses and the Red Sea'::text, 'God parts the sea so Moses can lead the Israelites to freedom. Dramatic reading.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/moses_red_sea.mp3'::text, 3, 12, 60, true),
  ('Daniel in the Lions Den'::text, 'Daniel prays to God and survives a night with hungry lions. Audio story.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/daniel_lions.mp3'::text, 4, 12, 70, true),
  ('The Good Samaritan'::text, 'Jesus teaches about loving your neighbor through a powerful parable. Dramatized.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/good_samaritan.mp3'::text, 3, 12, 80, true),
  ('The Prodigal Son'::text, 'A son wastes his inheritance, returns home, and finds his father running to meet him.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/prodigal_son.mp3'::text, 5, 12, 90, true),
  ('Jesus Feeds 5000'::text, 'Five loaves and two fish feed a crowd of thousands. Audio story for kids.'::text, 'bible_story'::text, NULL::text, 'https://archive.org/download/kids_bible_stories_librivox/feeds_5000.mp3'::text, 3, 12, 100, true)
) AS v(title, description, category, image_url, content_url, age_min, age_max, sort_order, is_free)
WHERE NOT EXISTS (SELECT 1 FROM public.kids_zone_resources WHERE kids_zone_resources.title = v.title);
