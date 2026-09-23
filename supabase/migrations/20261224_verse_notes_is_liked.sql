-- ============================================================================
-- 20261224_verse_notes_is_liked.sql
-- Reconcile the client's verse-note flag columns with the live table.
--
-- WHY: `lib/features/bible/data/bible_verse_service.dart` selects and writes
-- `is_liked` next to `is_bookmark`/`is_favorite` (fetchVerseNotes +
-- setVerseFlag), but `verse_notes` was created (20260803) WITHOUT `is_liked`.
-- The original patch (20260950_bible_verse_like.sql) is listed in deploy.ps1
-- but was evidently never applied to the live database, so every read/write
-- fails with 42703 `column verse_notes.is_liked does not exist`
-- ("Fetch verse notes error" + "Set verse flag error").
--
-- Live columns before this migration (verified via information_schema):
--   id, user_id, translation_id, book_id, chapter, verse, note,
--   is_bookmark, is_favorite, tags, created_at, updated_at
-- -> only `is_liked` is genuinely missing.
--
-- Idempotent: safe to re-run.
-- ============================================================================

ALTER TABLE public.verse_notes
  ADD COLUMN IF NOT EXISTS is_liked boolean NOT NULL DEFAULT false;

-- Defensive no-ops in case a fresh/partial schema is missing a column the
-- client also reads. `IF NOT EXISTS` leaves existing columns (and their types)
-- untouched.
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS is_bookmark boolean DEFAULT false;
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS is_favorite boolean DEFAULT false;
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS tags text[];
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS chapter integer;
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS verse integer;

CREATE INDEX IF NOT EXISTS idx_verse_notes_liked
  ON public.verse_notes (user_id, is_liked)
  WHERE is_liked = true;
