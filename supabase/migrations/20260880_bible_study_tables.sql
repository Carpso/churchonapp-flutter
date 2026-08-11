-- Create missing Bible Study tables + verse/streak tables that the app
-- queries but were never created by a migration.

-- 1. bible_studies (used by BibleStudyService)
CREATE TABLE IF NOT EXISTS public.bible_studies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  date DATE NOT NULL,
  time TEXT,
  leader TEXT,
  location TEXT,
  materials_url TEXT,
  max_attendees INT DEFAULT 0,
  current_attendees INT DEFAULT 0,
  status TEXT DEFAULT 'scheduled',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bible_studies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bible_studies_select" ON public.bible_studies;
CREATE POLICY "bible_studies_select" ON public.bible_studies
  FOR SELECT TO authenticated USING (
    tenant_id IS NULL
    OR tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin','employee','coa_employee'))
  );

DROP POLICY IF EXISTS "bible_studies_insert" ON public.bible_studies;
CREATE POLICY "bible_studies_insert" ON public.bible_studies
  FOR INSERT TO authenticated WITH CHECK (
    tenant_id IS NULL
    OR tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "bible_studies_update" ON public.bible_studies;
CREATE POLICY "bible_studies_update" ON public.bible_studies
  FOR UPDATE TO authenticated USING (
    tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin','employee','coa_employee'))
  );

DROP POLICY IF EXISTS "bible_studies_delete" ON public.bible_studies;
CREATE POLICY "bible_studies_delete" ON public.bible_studies
  FOR DELETE TO authenticated USING (
    tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin','employee','coa_employee'))
  );

-- 2. bible_study_attendance
CREATE TABLE IF NOT EXISTS public.bible_study_attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  study_id UUID REFERENCES public.bible_studies(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT,
  attended BOOLEAN DEFAULT false,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bible_study_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bible_study_attendance_select" ON public.bible_study_attendance;
CREATE POLICY "bible_study_attendance_select" ON public.bible_study_attendance
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "bible_study_attendance_insert" ON public.bible_study_attendance;
CREATE POLICY "bible_study_attendance_insert" ON public.bible_study_attendance
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "bible_study_attendance_update" ON public.bible_study_attendance;
CREATE POLICY "bible_study_attendance_update" ON public.bible_study_attendance
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- 3. increment_study_attendees RPC (used by attendStudy)
CREATE OR REPLACE FUNCTION public.increment_study_attendees(p_study_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.bible_studies
  SET current_attendees = current_attendees + 1
  WHERE id = p_study_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.increment_study_attendees(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_study_attendees(UUID) TO authenticated;

-- 4. user_study_streaks (used by streak service)
CREATE TABLE IF NOT EXISTS public.user_study_streaks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  current_streak INT DEFAULT 0,
  longest_streak INT DEFAULT 0,
  last_study_date DATE,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.user_study_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_study_streaks_select" ON public.user_study_streaks;
CREATE POLICY "user_study_streaks_select" ON public.user_study_streaks
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_study_streaks_insert" ON public.user_study_streaks;
CREATE POLICY "user_study_streaks_insert" ON public.user_study_streaks
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_study_streaks_update" ON public.user_study_streaks;
CREATE POLICY "user_study_streaks_update" ON public.user_study_streaks
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- 5. bible_verses (referenced by bible_verse_service + reader DB fallback).
-- NOTE: the actual KJV/NKJV/NLT text rows are seeded elsewhere (KJV batches +
-- 20260803 smart features). This just guarantees the table exists.
CREATE TABLE IF NOT EXISTS public.bible_verses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  translation_id UUID REFERENCES public.bible_translations(id) ON DELETE CASCADE,
  book_id UUID REFERENCES public.bible_books(id) ON DELETE CASCADE,
  book TEXT,
  chapter INT,
  verse INT,
  text TEXT,
  reference TEXT,
  search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english', coalesce(text,''))) STORED,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bible_verses_lookup ON public.bible_verses (translation_id, book_id, chapter, verse);
CREATE INDEX IF NOT EXISTS idx_bible_verses_search ON public.bible_verses USING GIN (search_vector);

ALTER TABLE public.bible_verses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bible_verses_select" ON public.bible_verses;
CREATE POLICY "bible_verses_select" ON public.bible_verses
  FOR SELECT TO authenticated USING (true);
