-- ============================================================================
-- 20261150_worship_lyrics.sql
-- Complete the Worship & Lyrics feature.
--
-- Real table: public.worship_lyrics (created by 20260723, extended by 20260840).
-- Gaps fixed here:
--   * The Flutter model reads/writes `musical_key`, `bpm`, `is_global` — none of
--     which exist on the table, so EVERY insert silently failed with 42703.
--   * No `is_published`, `media_url` (YouTube/media link), `views`, `likes`.
--   * RLS was `USING (true)` for SELECT and an unscoped leadership INSERT — any
--     tenant could read every other tenant's lyrics.
-- ============================================================================

-- ── 1. Columns ──────────────────────────────────────────────────────────────
ALTER TABLE public.worship_lyrics
  ADD COLUMN IF NOT EXISTS artist       text,
  ADD COLUMN IF NOT EXISTS category     text DEFAULT 'worship',
  ADD COLUMN IF NOT EXISTS language     text DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS musical_key  text,
  ADD COLUMN IF NOT EXISTS bpm          integer,
  ADD COLUMN IF NOT EXISTS media_url    text,
  ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_global    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_active    boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS views        integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS likes        integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at   timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_worship_lyrics_published
  ON public.worship_lyrics (is_published, is_global);

-- ── 2. Leadership gate (tenant-scoped, recursion-safe) ──────────────────────
-- Platform staff bypass tenant ownership. Everyone else must belong to the
-- lyric's tenant AND hold a leadership / worship role there.
CREATE OR REPLACE FUNCTION public.can_manage_worship_lyrics(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_admin_or_employee()
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id = p_tenant_id::text
        AND lower(coalesce(p.role, '')) IN (
          'admin', 'pastor', 'bishop', 'apostle', 'prophet',
          'general_secretary', 'general_treasurer', 'treasurer',
          'leader', 'department_leader', 'worship_leader',
          'praise_team_leader', 'praise_team_member',
          'assistant_pastor', 'assistant_bishop'
        )
    );
$$;

REVOKE EXECUTE ON FUNCTION public.can_manage_worship_lyrics(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_manage_worship_lyrics(uuid) TO authenticated;

-- ── 3. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.worship_lyrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view worship lyrics" ON public.worship_lyrics;
DROP POLICY IF EXISTS "Tenant admins can manage worship lyrics" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_select" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_insert" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_read" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_write" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_update" ON public.worship_lyrics;
DROP POLICY IF EXISTS "worship_lyrics_delete" ON public.worship_lyrics;

-- Readable by any authenticated user when published + (global or own tenant).
-- Unpublished rows are visible only to that tenant's leadership / platform staff.
CREATE POLICY "worship_lyrics_read" ON public.worship_lyrics
  FOR SELECT TO authenticated
  USING (
    public.is_admin_or_employee()
    OR (
      tenant_id::text = public.get_my_tenant_id()
      AND (is_published OR public.can_manage_worship_lyrics(tenant_id))
    )
    OR (is_global = true AND is_published = true)
  );

CREATE POLICY "worship_lyrics_insert" ON public.worship_lyrics
  FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_worship_lyrics(tenant_id));

CREATE POLICY "worship_lyrics_update" ON public.worship_lyrics
  FOR UPDATE TO authenticated
  USING (public.can_manage_worship_lyrics(tenant_id))
  WITH CHECK (public.can_manage_worship_lyrics(tenant_id));

CREATE POLICY "worship_lyrics_delete" ON public.worship_lyrics
  FOR DELETE TO authenticated
  USING (public.can_manage_worship_lyrics(tenant_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.worship_lyrics TO authenticated;

-- ── 4. Likes (deduped per user) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.worship_lyric_likes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lyric_id   uuid NOT NULL REFERENCES public.worship_lyrics(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lyric_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_worship_lyric_likes_lyric
  ON public.worship_lyric_likes (lyric_id);

ALTER TABLE public.worship_lyric_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "worship_lyric_likes_read" ON public.worship_lyric_likes;
CREATE POLICY "worship_lyric_likes_read" ON public.worship_lyric_likes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin_or_employee());

GRANT SELECT ON public.worship_lyric_likes TO authenticated;

-- ── 5. Counter RPCs (SECURITY DEFINER so members can't UPDATE rows) ─────────
CREATE OR REPLACE FUNCTION public.increment_lyric_view(p_lyric_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v integer;
BEGIN
  UPDATE public.worship_lyrics
     SET views = coalesce(views, 0) + 1
   WHERE id = p_lyric_id
  RETURNING views INTO v;
  RETURN coalesce(v, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.toggle_lyric_like(p_lyric_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _liked boolean;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  DELETE FROM public.worship_lyric_likes
   WHERE lyric_id = p_lyric_id AND user_id = _uid;

  IF FOUND THEN
    UPDATE public.worship_lyrics
       SET likes = greatest(coalesce(likes, 0) - 1, 0)
     WHERE id = p_lyric_id;
    _liked := false;
  ELSE
    INSERT INTO public.worship_lyric_likes (lyric_id, user_id)
    VALUES (p_lyric_id, _uid)
    ON CONFLICT (lyric_id, user_id) DO NOTHING;

    IF FOUND THEN
      UPDATE public.worship_lyrics
         SET likes = coalesce(likes, 0) + 1
       WHERE id = p_lyric_id;
    END IF;
    _liked := true;
  END IF;

  RETURN _liked;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.increment_lyric_view(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.toggle_lyric_like(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_lyric_view(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_lyric_like(uuid) TO authenticated;

-- ── 6. Realtime (management list live-updates) ──────────────────────────────
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.worship_lyrics;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
