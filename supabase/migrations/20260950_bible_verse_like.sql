-- 20260950 — Bible "Like" support on verse_notes
ALTER TABLE public.verse_notes ADD COLUMN IF NOT EXISTS is_liked BOOLEAN NOT NULL DEFAULT false;