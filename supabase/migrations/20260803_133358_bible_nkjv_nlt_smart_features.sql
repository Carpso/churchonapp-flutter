-- ============================================================
-- CHURCH ON APP - BIBLE FEATURE ENHANCEMENT
-- Adds NKJV & NLT translations, bible_chapters table,
-- full-text search, reading plans, verse notes, cross-refs,
-- and AI-powered chapter summaries.
-- ============================================================

BEGIN;

-- ── 1. ADD NKJV & NLT TRANSLATIONS ──────────────────

INSERT INTO public.bible_translations (code, name, full_name, language_code, is_public_domain, copyright_info)
VALUES
  ('nkjv', 'New King James Version', 'New King James Version', 'en', false, 'Copyright 1982 Thomas Nelson, Inc. Used by permission. All rights reserved.'),
  ('nlt', 'New Living Translation', 'New Living Translation', 'en', false, 'Copyright 1996, 2004, 2007, 2013 Tyndale House Foundation. Used by permission of Tyndale House Publishers, Inc.')
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  full_name = EXCLUDED.full_name,
  is_public_domain = EXCLUDED.is_public_domain,
  copyright_info = EXCLUDED.copyright_info;

-- ── 2. CREATE BIBLE CHAPTERS TABLE ──────────────────────────

CREATE TABLE IF NOT EXISTS public.bible_chapters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
  translation_id UUID NOT NULL REFERENCES public.bible_translations(id) ON DELETE CASCADE,
  chapter_number INTEGER NOT NULL,
  verse_count INTEGER NOT NULL DEFAULT 0,
  word_count INTEGER NOT NULL DEFAULT 0,
  summary TEXT,
  key_themes TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(book_id, translation_id, chapter_number)
);

ALTER TABLE public.bible_chapters ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "bible_chapters_select" ON public.bible_chapters FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_bible_chapters_book ON public.bible_chapters(book_id, translation_id);
CREATE INDEX IF NOT EXISTS idx_bible_chapters_summary ON public.bible_chapters USING GIN(to_tsvector('english', COALESCE(summary, '')));

-- ── 3. FULL-TEXT SEARCH ON bible_verses ─────────────────────

ALTER TABLE public.bible_verses ADD COLUMN IF NOT EXISTS search_vector TSVECTOR;

CREATE OR REPLACE FUNCTION bible_verses_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('english', COALESCE(NEW.text, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.reference, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE((SELECT name FROM bible_books WHERE id = NEW.book_id), '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bible_verses_search_vector ON public.bible_verses;
CREATE TRIGGER trg_bible_verses_search_vector
  BEFORE INSERT OR UPDATE ON public.bible_verses
  FOR EACH ROW
  EXECUTE FUNCTION bible_verses_search_vector();

CREATE INDEX IF NOT EXISTS idx_bible_verses_search_vector ON public.bible_verses USING GIN(search_vector);

UPDATE public.bible_verses SET search_vector =
  setweight(to_tsvector('english', COALESCE(text, '')), 'A') ||
  setweight(to_tsvector('english', COALESCE(reference, '')), 'B') ||
  setweight(to_tsvector('english', COALESCE((SELECT name FROM bible_books WHERE bible_books.id = bible_verses.book_id), '')), 'C')
WHERE search_vector IS NULL;

-- ── 4. READING PLANS (handle existing table) ──────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='created_by') THEN
    ALTER TABLE public.reading_plans ADD COLUMN created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='plan_type') THEN
    ALTER TABLE public.reading_plans ADD COLUMN plan_type TEXT NOT NULL DEFAULT 'sequential';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='day_count') THEN
    ALTER TABLE public.reading_plans ADD COLUMN day_count INTEGER NOT NULL DEFAULT 365;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='start_date') THEN
    ALTER TABLE public.reading_plans ADD COLUMN start_date DATE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='updated_at') THEN
    ALTER TABLE public.reading_plans ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reading_plans' AND column_name='is_active') THEN
    ALTER TABLE public.reading_plans ADD COLUMN is_active BOOLEAN DEFAULT true;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

ALTER TABLE public.reading_plans ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "reading_plans_select" ON public.reading_plans FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "reading_plans_insert" ON public.reading_plans FOR INSERT WITH CHECK (
    auth.uid() = created_by OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_reading_plans_tenant ON public.reading_plans(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reading_plans_active ON public.reading_plans(is_active);

-- ── 5. READING PLAN DAILY ENTRIES ──────────────────────────

CREATE TABLE IF NOT EXISTS public.reading_plan_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES public.reading_plans(id) ON DELETE CASCADE,
  day_number INTEGER NOT NULL,
  book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
  chapter INTEGER NOT NULL,
  verse_start INTEGER,
  verse_end INTEGER,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id, day_number)
);

ALTER TABLE public.reading_plan_entries ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "reading_plan_entries_select" ON public.reading_plan_entries FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_reading_plan_entries_plan ON public.reading_plan_entries(plan_id);

-- ── 6. VERSE NOTES & BOOKMARKS ──────────────────────────────

CREATE TABLE IF NOT EXISTS public.verse_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  translation_id UUID REFERENCES public.bible_translations(id) ON DELETE SET NULL,
  book_id UUID REFERENCES public.bible_books(id) ON DELETE CASCADE,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  note TEXT NOT NULL,
  is_bookmark BOOLEAN DEFAULT false,
  is_favorite BOOLEAN DEFAULT false,
  tags TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.verse_notes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "verse_notes_select_own" ON public.verse_notes FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "verse_notes_insert_own" ON public.verse_notes FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "verse_notes_update_own" ON public.verse_notes FOR UPDATE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "verse_notes_delete_own" ON public.verse_notes FOR DELETE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_verse_notes_user ON public.verse_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_verse_notes_book_chapter ON public.verse_notes(book_id, chapter, verse);
CREATE INDEX IF NOT EXISTS idx_verse_notes_bookmark ON public.verse_notes(user_id, is_bookmark) WHERE is_bookmark = true;
CREATE INDEX IF NOT EXISTS idx_verse_notes_tags ON public.verse_notes USING GIN(tags);

-- ── 7. CROSS-REFERENCES ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cross_references (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
  source_chapter INTEGER NOT NULL,
  source_verse INTEGER NOT NULL,
  target_book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
  target_chapter INTEGER NOT NULL,
  target_verse INTEGER NOT NULL,
  reference_type TEXT DEFAULT 'parallel' CHECK (reference_type IN ('parallel', 'fulfillment', 'prophecy', 'thematic', 'word_study')),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.cross_references ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "cross_references_select" ON public.cross_references FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_cross_refs_source ON public.cross_references(source_book_id, source_chapter, source_verse);
CREATE INDEX IF NOT EXISTS idx_cross_refs_target ON public.cross_references(target_book_id, target_chapter, target_verse);
CREATE INDEX IF NOT EXISTS idx_cross_refs_type ON public.cross_references(reference_type);

-- ── 8. AI-POWERED CHAPTER SUMMARIES ─────────────────────────

CREATE TABLE IF NOT EXISTS public.bible_chapter_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES public.bible_books(id) ON DELETE CASCADE,
  translation_id UUID REFERENCES public.bible_translations(id) ON DELETE SET NULL,
  chapter_number INTEGER NOT NULL,
  summary TEXT NOT NULL,
  key_verses TEXT[],
  themes TEXT[],
  ai_model TEXT DEFAULT 'kael',
  generated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(book_id, translation_id, chapter_number)
);

ALTER TABLE public.bible_chapter_summaries ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "bible_chapter_summaries_select" ON public.bible_chapter_summaries FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "bible_chapter_summaries_insert" ON public.bible_chapter_summaries FOR INSERT WITH CHECK (
    auth.uid() = generated_by OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_bible_chapter_summaries_book ON public.bible_chapter_summaries(book_id, chapter_number);
CREATE INDEX IF NOT EXISTS idx_bible_chapter_summaries_tenant ON public.bible_chapter_summaries(tenant_id);

-- ── 9. TRIGGERS FOR updated_at ─────────────────────────────

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bible_chapters_updated_at ON public.bible_chapters;
CREATE TRIGGER trg_bible_chapters_updated_at
  BEFORE UPDATE ON public.bible_chapters
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_verse_notes_updated_at ON public.verse_notes;
CREATE TRIGGER trg_verse_notes_updated_at
  BEFORE UPDATE ON public.verse_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_bible_chapter_summaries_updated_at ON public.bible_chapter_summaries;
CREATE TRIGGER trg_bible_chapter_summaries_updated_at
  BEFORE UPDATE ON public.bible_chapter_summaries
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;