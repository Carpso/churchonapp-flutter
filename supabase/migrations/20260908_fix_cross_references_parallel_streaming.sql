-- Fix cross-references, parallel translations & cloudflare streaming wiring.
--
-- 1. cross_references was an empty shell (0 rows, SELECT-only policy, no unique
--    index) — the verse-sheet feature always showed "No cross-references found".
--    This migration:
--      * seeds the table with curated cross-references (incl. the 59 curated
--        harmony/fulfillment pairs from the app's kLinkedScripture data)
--      * adds a unique index on (source,target,type) so kael-AI-generated refs
--        can UPSERT without duplicating
--      * opens an authenticated INSERT policy so users/kael can persist refs
--      * backfills reverse direction (target→source) rows so any verse in a
--        pair surfaces its counterpart (bidirectional cross-referencing)
-- 2. live_streams.status CHECK was `('scheduled','live','ended')` but the app
--    writes 'archived' when purging old recordings → every cleanup insert
--    failed with 23514. Widened to include 'archived'.

-- ─── cross_references: unique pair index ───────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS ux_cross_references_pair
  ON public.cross_references(
    source_book_id, source_chapter, source_verse,
    target_book_id, target_chapter, target_verse, reference_type
  );

-- ─── cross_references: authenticated INSERT policy (kael + users) ──────
DO $$ BEGIN
  CREATE POLICY "cross_references_insert_authenticated"
    ON public.cross_references FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── live_streams.status: allow 'archived' ──────────────────────────────
ALTER TABLE public.live_streams DROP CONSTRAINT IF EXISTS live_streams_status_check;
ALTER TABLE public.live_streams ADD CONSTRAINT live_streams_status_check
  CHECK (status IN ('scheduled', 'live', 'ended', 'archived'));

-- ─── curated cross-references seed ──────────────────────────────────────
-- Books are referenced by canonical bible_books.name. Uses a VALUES list so
-- the seed stays readable & idempotent (ON CONFLICT DO NOTHING).
WITH seed(source_name, s_ch, s_v, target_name, t_ch, t_v, type) AS (
  VALUES
    -- Harmony (parallel Gospel accounts)
    ('Matthew', 5, 3,   'Luke', 6, 20,  'parallel'),
    ('Matthew', 5, 11,  'Luke', 6, 22,  'parallel'),
    ('Matthew', 6, 9,   'Luke', 11, 2,  'parallel'),
    ('Matthew', 7, 7,   'Luke', 11, 9,  'parallel'),
    ('Matthew', 3, 13,  'Mark', 1, 9,   'parallel'),
    ('Matthew', 3, 13,  'Luke', 3, 21,  'parallel'),
    ('Matthew', 13, 31, 'Mark', 4, 30,  'parallel'),
    ('Matthew', 13, 31, 'Luke', 13, 18, 'parallel'),
    ('Matthew', 16, 15, 'Mark', 8, 29,  'parallel'),
    ('Matthew', 16, 15, 'Luke', 9, 20,  'parallel'),
    ('Matthew', 16, 24, 'Mark', 8, 34,  'parallel'),
    ('Matthew', 16, 24, 'Luke', 9, 23,  'parallel'),
    ('Matthew', 17, 1,  'Mark', 9, 2,   'parallel'),
    ('Matthew', 17, 1,  'Luke', 9, 28,  'parallel'),
    ('Matthew', 19, 13, 'Mark', 10, 13, 'parallel'),
    ('Matthew', 19, 13, 'Luke', 18, 15, 'parallel'),
    ('Matthew', 21, 12, 'Mark', 11, 15, 'parallel'),
    ('Matthew', 21, 12, 'Luke', 19, 45, 'parallel'),
    ('Matthew', 26, 26, 'Mark', 14, 22, 'parallel'),
    ('Matthew', 26, 26, 'Luke', 22, 19, 'parallel'),
    ('Matthew', 26, 39, 'Mark', 14, 36, 'parallel'),
    ('Matthew', 26, 39, 'Luke', 22, 42, 'parallel'),
    ('Matthew', 27, 46, 'Mark', 15, 34, 'parallel'),
    -- Prophecy / fulfillment (OT → NT)
    ('Isaiah',   7, 14,  'Matthew', 1, 22, 'prophecy'),
    ('Micah',    5, 2,   'Matthew', 2, 5,  'prophecy'),
    ('Hosea',    11, 1,  'Matthew', 2, 15, 'prophecy'),
    ('Jeremiah', 31, 15, 'Matthew', 2, 17, 'prophecy'),
    ('Isaiah',   40, 3,  'Matthew', 3, 3,  'prophecy'),
    ('Isaiah',   9, 1,   'Matthew', 4, 14, 'prophecy'),
    ('Isaiah',   53, 4,  'Matthew', 8, 16, 'prophecy'),
    ('Malachi',  3, 1,   'Matthew', 11, 10,'prophecy'),
    ('Jonah',    1, 17,  'Matthew', 12, 40,'prophecy'),
    ('Isaiah',   6, 9,   'Matthew', 13, 14,'prophecy'),
    ('Psalms',   78, 2,  'Matthew', 13, 35,'prophecy'),
    ('Isaiah',   53, 12, 'Luke',    22, 37,'prophecy'),
    ('Isaiah',   61, 1,  'Luke',    4, 18, 'prophecy'),
    ('Psalms',   118, 26,'Matthew', 21, 9, 'prophecy'),
    ('Zechariah',9, 9,   'Matthew', 21, 4, 'prophecy'),
    ('Zechariah',9, 9,   'John',    12, 14,'prophecy'),
    ('Psalms',   22, 18, 'Matthew', 27, 35,'prophecy'),
    ('Psalms',   22, 1,  'Matthew', 27, 46,'prophecy'),
    ('Psalms',   69, 21, 'John',    19, 28,'prophecy'),
    ('Psalms',   34, 20, 'John',    19, 36,'prophecy'),
    ('Zechariah',12, 10, 'John',    19, 37,'prophecy'),
    ('Psalms',   41, 9,  'John',    13, 18,'prophecy'),
    ('Psalms',   69, 9,  'John',    2, 17, 'prophecy'),
    ('Psalms',   69, 4,  'John',    15, 25,'prophecy'),
    ('Psalms',   110, 1, 'Matthew', 22, 44,'prophecy'),
    ('Psalms',   16, 10, 'Acts',    2, 27, 'prophecy'),
    ('Isaiah',   53, 7,  'Acts',    8, 32, 'prophecy'),
    -- Classic theologically-linked passages
    ('Genesis',  1, 1,   'John',    1, 1,  'thematic'),
    ('Genesis',  1, 1,   'John',    1, 14, 'thematic'),
    ('Psalms',   23, 1,  'John',    10, 11,'thematic'),
    ('Psalms',   23, 1,  'Hebrews', 13, 20,'thematic'),
    ('John',     14, 6,  'Acts',    4, 12, 'thematic'),
    ('Romans',   8, 28,  'Philippians', 1, 6, 'thematic'),
    ('Romans',   3, 23,  'Romans',  6, 23, 'thematic'),
    ('Romans',   6, 23,  'John',    3, 16, 'thematic'),
    ('John',     3, 16,  '1 John',  4, 9,  'thematic'),
    ('Ephesians',2, 8,   'Titus',   3, 5,  'thematic'),
    ('Ephesians',2, 8,   'Romans',  5, 1,  'thematic'),
    ('Hebrews',  11, 1,  'Romans',  8, 24, 'thematic'),
    ('James',    2, 17,  'Galatians', 5, 6, 'thematic'),
    ('Matthew',  22, 37, 'Deuteronomy', 6, 5, 'thematic'),
    ('Matthew',  22, 39, 'Leviticus', 19, 18, 'thematic'),
    ('Matthew',  4, 4,   'Deuteronomy', 8, 3, 'thematic'),
    ('Matthew',  4, 7,   'Deuteronomy', 6, 16, 'thematic'),
    ('Matthew',  4, 10,  'Deuteronomy', 6, 13, 'thematic'),
    ('Psalms',   23, 1,  'Isaiah', 40, 11,'thematic'),
    ('2 Timothy',3, 16,  'Hebrews', 4, 12, 'thematic'),
    ('Jeremiah', 29, 11, 'Romans', 11, 29, 'thematic'),
    ('Proverbs', 3, 5,   'Philippians', 4, 6, 'thematic'),
    ('Proverbs', 3, 5,   'Isaiah', 55, 8, 'thematic'),
    ('Galatians',5, 22,  'Romans', 15, 13, 'thematic'),
    ('Psalms',   119, 105,'Psalms', 19, 8, 'thematic'),
    ('Psalms',   119, 105,'Hebrews', 4, 12, 'thematic')
)
-- Insert forward direction (source → target) and keep it idempotent.
INSERT INTO public.cross_references (
  source_book_id, source_chapter, source_verse,
  target_book_id, target_chapter, target_verse, reference_type
)
SELECT
  sb.id, sd.s_ch, sd.s_v,
  tb.id, sd.t_ch, sd.t_v, sd.type
FROM seed sd
JOIN public.bible_books sb ON lower(sb.name) = lower(sd.source_name)
JOIN public.bible_books tb ON lower(tb.name) = lower(sd.target_name)
ON CONFLICT (
  source_book_id, source_chapter, source_verse,
  target_book_id, target_chapter, target_verse, reference_type
) DO NOTHING;

-- Backfill reverse direction so BOTH sides of every pair are discoverable.
INSERT INTO public.cross_references (
  source_book_id, source_chapter, source_verse,
  target_book_id, target_chapter, target_verse, reference_type
)
SELECT
  cr.target_book_id, cr.target_chapter, cr.target_verse,
  cr.source_book_id, cr.source_chapter, cr.source_verse,
  cr.reference_type
FROM public.cross_references cr
WHERE NOT EXISTS (
  SELECT 1 FROM public.cross_references rev
  WHERE rev.source_book_id = cr.target_book_id
    AND rev.source_chapter = cr.target_chapter
    AND rev.source_verse = cr.target_verse
    AND rev.target_book_id = cr.source_book_id
    AND rev.target_chapter = cr.source_chapter
    AND rev.target_verse = cr.source_verse
    AND rev.reference_type = cr.reference_type
)
ON CONFLICT (
  source_book_id, source_chapter, source_verse,
  target_book_id, target_chapter, target_verse, reference_type
) DO NOTHING;