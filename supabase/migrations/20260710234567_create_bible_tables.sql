-- ═══════════════════════════════════════════════════════════════════════════════
-- CREATE BIBLE TABLES
-- Creates bible_translations, bible_books, and bible_audio_files tables
-- that were referenced by seed migrations but never created.
-- Uses IF NOT EXISTS for safe re-runs.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Bible Translations
CREATE TABLE IF NOT EXISTS public.bible_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    is_public_domain BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Bible Books
CREATE TABLE IF NOT EXISTS public.bible_books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    abbreviation TEXT NOT NULL,
    testament TEXT NOT NULL CHECK (testament IN ('OT', 'NT')),
    book_order INTEGER NOT NULL,
    testament_order TEXT NOT NULL CHECK (testament_order IN ('OT', 'NT')),
    chapters INTEGER NOT NULL,
    description TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Bible Audio Files
CREATE TABLE IF NOT EXISTS public.bible_audio_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_id UUID NOT NULL REFERENCES public.bible_translations(id) ON DELETE CASCADE,
    book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
    chapter INTEGER NOT NULL CHECK (chapter > 0),
    storage_provider TEXT NOT NULL DEFAULT 'r2',
    storage_bucket TEXT DEFAULT '',
    storage_path TEXT NOT NULL,
    file_size_bytes INTEGER DEFAULT 0,
    duration_seconds NUMERIC DEFAULT 0,
    format TEXT NOT NULL DEFAULT 'mp3',
    sample_rate INTEGER DEFAULT 22050,
    voice_name TEXT DEFAULT '',
    generation_status TEXT NOT NULL DEFAULT 'pending' CHECK (generation_status IN ('pending', 'processing', 'completed', 'failed')),
    generated_at TIMESTAMPTZ,
    uploaded_at TIMESTAMPTZ,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    church_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (translation_id, book_id, chapter, storage_provider)
);

-- 4. Seed the KJV translation (needed by seed_bible_data migration)
INSERT INTO public.bible_translations (code, name, is_public_domain)
SELECT 'kjv', 'King James Version', true
WHERE NOT EXISTS (SELECT 1 FROM public.bible_translations WHERE code = 'kjv');

INSERT INTO public.bible_translations (code, name, is_public_domain)
SELECT 'web', 'World English Bible', true
WHERE NOT EXISTS (SELECT 1 FROM public.bible_translations WHERE code = 'web');

-- 5. Enable RLS (mirrors existing policy patterns)
ALTER TABLE public.bible_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bible_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bible_audio_files ENABLE ROW LEVEL SECURITY;

-- 6. RLS policies: allow authenticated users to read all, admins to write
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bible_translations' AND policyname = 'Anyone can read bible_translations') THEN
    CREATE POLICY "Anyone can read bible_translations" ON public.bible_translations FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bible_books' AND policyname = 'Anyone can read bible_books') THEN
    CREATE POLICY "Anyone can read bible_books" ON public.bible_books FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bible_audio_files' AND policyname = 'Anyone can read bible_audio_files') THEN
    CREATE POLICY "Anyone can read bible_audio_files" ON public.bible_audio_files FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bible_audio_files' AND policyname = 'Authenticated users can insert bible_audio_files') THEN
    CREATE POLICY "Authenticated users can insert bible_audio_files" ON public.bible_audio_files FOR INSERT WITH CHECK (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bible_audio_files' AND policyname = 'Owners can update bible_audio_files') THEN
    CREATE POLICY "Owners can update bible_audio_files" ON public.bible_audio_files FOR UPDATE USING (auth.role() = 'authenticated');
  END IF;
END $$;
