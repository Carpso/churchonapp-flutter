-- KJV Bible text seed (31,102 verses)
-- The full 7.3MB seed was split into 11 batches (20260711000004_seed_kjjv_text_p001..p011)
-- because a single query exceeds the Supabase API request size limit (413).
-- All 31,102 verses are loaded by those batches; this file is intentionally a no-op.
SELECT COUNT(*) AS kjv_verses_seeded FROM public.bible_verses;
