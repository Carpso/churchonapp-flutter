-- 1. Add user_name and user_avatar to klip_comments (used by kingdom_klips_screen.dart)
ALTER TABLE IF EXISTS public.klip_comments ADD COLUMN IF NOT EXISTS user_name TEXT;
ALTER TABLE IF EXISTS public.klip_comments ADD COLUMN IF NOT EXISTS user_avatar TEXT;

-- 2. SAVED KLIPS TABLE
CREATE TABLE IF NOT EXISTS public.saved_klips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    klip_id UUID NOT NULL REFERENCES public.klips(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, klip_id)
);

ALTER TABLE public.saved_klips ENABLE ROW LEVEL SECURITY;

-- Users can read their own saved klips
DO $$
BEGIN
    DROP POLICY IF EXISTS "saved_klips_select_own" ON public.saved_klips;
    CREATE POLICY "saved_klips_select_own" ON public.saved_klips
        FOR SELECT TO authenticated USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL;
END $$;

-- Users can insert their own saved klips
DO $$
BEGIN
    DROP POLICY IF EXISTS "saved_klips_insert_own" ON public.saved_klips;
    CREATE POLICY "saved_klips_insert_own" ON public.saved_klips
        FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL;
END $$;

-- Users can delete their own saved klips
DO $$
BEGIN
    DROP POLICY IF EXISTS "saved_klips_delete_own" ON public.saved_klips;
    CREATE POLICY "saved_klips_delete_own" ON public.saved_klips
        FOR DELETE TO authenticated USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_saved_klips_user ON public.saved_klips(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_klips_klip ON public.saved_klips(klip_id);

-- 3. View increment function for klips (used by kingdom_klips_screen)
CREATE OR REPLACE FUNCTION public.increment_klip_view(p_klip_id UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE public.klips SET views = COALESCE(views, 0) + 1 WHERE id = p_klip_id;
END;
$$;
