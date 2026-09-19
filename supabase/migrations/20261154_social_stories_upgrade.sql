-- ============================================================================
-- 20261154_social_stories_upgrade.sql
-- Stories upgrade: variable durations, reactions, archive + highlights.
--
--   * duration_hours (default 24, clamped 1..8760 = max 1 year). `expires_at`
--     is DERIVED server-side by a trigger so the client can never set an
--     arbitrary far-future expiry. Old rows keep working: the column is added
--     with a default and the existing `expires_at` values are left untouched
--     (the trigger only recomputes on insert / when duration changes).
--   * social_story_reactions: one reaction per (story, user), owner sees the
--     aggregate.
--   * social_stories.is_archived: own stories are archived by default so the
--     poster keeps an "archive" of past (even expired) stories.
--   * story_highlights + story_highlight_items: persistent highlight reels.
-- ============================================================================

-- ── 1. Durations ────────────────────────────────────────────────────────────
ALTER TABLE public.social_stories
  ADD COLUMN IF NOT EXISTS duration_hours int NOT NULL DEFAULT 24;

DO $$
BEGIN
  ALTER TABLE public.social_stories
    ADD CONSTRAINT social_stories_duration_hours_check
    CHECK (duration_hours BETWEEN 1 AND 8760);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Derived expiry: a single source of truth, capped at 1 year.
CREATE OR REPLACE FUNCTION public.enforce_story_expiry()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.duration_hours IS NULL THEN NEW.duration_hours := 24; END IF;
  IF NEW.duration_hours < 1 THEN NEW.duration_hours := 1; END IF;
  IF NEW.duration_hours > 8760 THEN NEW.duration_hours := 8760; END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.expires_at := COALESCE(NEW.created_at, now())
      + make_interval(hours => NEW.duration_hours);
  ELSIF NEW.duration_hours IS DISTINCT FROM OLD.duration_hours THEN
    NEW.expires_at := COALESCE(NEW.created_at, now())
      + make_interval(hours => NEW.duration_hours);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_story_expiry ON public.social_stories;
CREATE TRIGGER trg_enforce_story_expiry
  BEFORE INSERT OR UPDATE ON public.social_stories
  FOR EACH ROW EXECUTE FUNCTION public.enforce_story_expiry();

-- Change the lifetime of an existing own story (server-clamped).
CREATE OR REPLACE FUNCTION public.set_story_expiry(p_story_id uuid, p_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_hours int;
  v_exp   timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  v_hours := GREATEST(1, LEAST(COALESCE(p_hours, 24), 8760));

  UPDATE public.social_stories
     SET duration_hours = v_hours,
         expires_at = COALESCE(created_at, now())
                      + make_interval(hours => v_hours)
   WHERE id = p_story_id AND user_id = v_uid
   RETURNING expires_at INTO v_exp;

  IF v_exp IS NULL THEN RAISE EXCEPTION 'story_not_found_or_not_owner'; END IF;
  RETURN v_exp;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_story_expiry(uuid, int) FROM anon;

-- ── 2. Reactions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.social_story_reactions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id   uuid NOT NULL REFERENCES public.social_stories(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction   text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_story_reactions_story
  ON public.social_story_reactions (story_id, created_at DESC);

ALTER TABLE public.social_story_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "story_reactions_read_own" ON public.social_story_reactions;
CREATE POLICY "story_reactions_read_own"
  ON public.social_story_reactions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "story_reactions_owner_read" ON public.social_story_reactions;
CREATE POLICY "story_reactions_owner_read"
  ON public.social_story_reactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.social_stories s
      WHERE s.id = social_story_reactions.story_id AND s.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "story_reactions_write_own" ON public.social_story_reactions;
CREATE POLICY "story_reactions_write_own"
  ON public.social_story_reactions FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND reaction = ANY (ARRAY['❤️', '🙏', '🔥', '😂', '👏'])
  );

-- Toggle one reaction per story per user.
CREATE OR REPLACE FUNCTION public.react_to_story(p_story_id uuid, p_reaction text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_existing text;
  v_count    int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_reaction IS NULL OR NOT (p_reaction = ANY (ARRAY['❤️', '🙏', '🔥', '😂', '👏'])) THEN
    RAISE EXCEPTION 'invalid_reaction';
  END IF;

  SELECT reaction INTO v_existing
    FROM public.social_story_reactions
   WHERE story_id = p_story_id AND user_id = v_uid;

  IF v_existing = p_reaction THEN
    DELETE FROM public.social_story_reactions
     WHERE story_id = p_story_id AND user_id = v_uid;
  ELSE
    INSERT INTO public.social_story_reactions (story_id, user_id, reaction)
    VALUES (p_story_id, v_uid, p_reaction)
    ON CONFLICT (story_id, user_id)
      DO UPDATE SET reaction = EXCLUDED.reaction, created_at = now();
  END IF;

  SELECT count(*) INTO v_count
    FROM public.social_story_reactions WHERE story_id = p_story_id;

  RETURN jsonb_build_object(
    'my_reaction', CASE WHEN v_existing = p_reaction THEN NULL ELSE p_reaction END,
    'count', v_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.react_to_story(uuid, text) FROM anon;

-- Aggregate counts (anonymous, safe for any authenticated viewer).
CREATE OR REPLACE FUNCTION public.story_reaction_summary(p_story_id uuid)
RETURNS TABLE (reaction text, cnt bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT reaction, count(*)::bigint AS cnt
    FROM public.social_story_reactions
   WHERE story_id = p_story_id
   GROUP BY reaction
   ORDER BY cnt DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.story_reaction_summary(uuid) FROM anon;

-- ── 3. Archive ──────────────────────────────────────────────────────────────
ALTER TABLE public.social_stories
  ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_social_stories_archive
  ON public.social_stories (user_id, is_archived, created_at DESC);

CREATE OR REPLACE FUNCTION public.set_story_archived(p_story_id uuid, p_archived boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_val boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  UPDATE public.social_stories
     SET is_archived = COALESCE(p_archived, true)
   WHERE id = p_story_id AND user_id = v_uid
   RETURNING is_archived INTO v_val;
  IF v_val IS NULL THEN RAISE EXCEPTION 'story_not_found_or_not_owner'; END IF;
  RETURN v_val;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_story_archived(uuid, boolean) FROM anon;

-- ── 4. Highlights ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_highlights (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title      text NOT NULL,
  cover_url  text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_story_highlights_user
  ON public.story_highlights (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.story_highlight_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  highlight_id uuid NOT NULL REFERENCES public.story_highlights(id) ON DELETE CASCADE,
  story_id     uuid NOT NULL REFERENCES public.social_stories(id) ON DELETE CASCADE,
  position     int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (highlight_id, story_id)
);

CREATE INDEX IF NOT EXISTS idx_story_highlight_items
  ON public.story_highlight_items (highlight_id, position);

ALTER TABLE public.story_highlights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_highlight_items ENABLE ROW LEVEL SECURITY;

-- Highlights are profile-persistent and readable by signed-in users.
DROP POLICY IF EXISTS "story_highlights_read" ON public.story_highlights;
CREATE POLICY "story_highlights_read"
  ON public.story_highlights FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "story_highlights_owner_write" ON public.story_highlights;
CREATE POLICY "story_highlights_owner_write"
  ON public.story_highlights FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "story_highlight_items_read" ON public.story_highlight_items;
CREATE POLICY "story_highlight_items_read"
  ON public.story_highlight_items FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "story_highlight_items_owner_write" ON public.story_highlight_items;
CREATE POLICY "story_highlight_items_owner_write"
  ON public.story_highlight_items FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.story_highlights h
      WHERE h.id = story_highlight_items.highlight_id AND h.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.story_highlights h
      WHERE h.id = story_highlight_items.highlight_id AND h.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.create_story_highlight(
  p_title      text,
  p_cover_url  text DEFAULT NULL,
  p_story_ids  uuid[] DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_sid uuid;
  v_pos int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_title IS NULL OR btrim(p_title) = '' THEN RAISE EXCEPTION 'title_required'; END IF;

  INSERT INTO public.story_highlights (user_id, title, cover_url)
  VALUES (v_uid, btrim(p_title), p_cover_url)
  RETURNING id INTO v_id;

  IF p_story_ids IS NOT NULL THEN
    FOREACH v_sid IN ARRAY p_story_ids LOOP
      IF EXISTS (SELECT 1 FROM public.social_stories s
                  WHERE s.id = v_sid AND s.user_id = v_uid) THEN
        INSERT INTO public.story_highlight_items (highlight_id, story_id, position)
        VALUES (v_id, v_sid, v_pos)
        ON CONFLICT (highlight_id, story_id) DO NOTHING;
        v_pos := v_pos + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_story_highlight(text, text, uuid[]) FROM anon;

CREATE OR REPLACE FUNCTION public.update_story_highlight(
  p_highlight_id uuid,
  p_title        text,
  p_cover_url    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  UPDATE public.story_highlights
     SET title = COALESCE(NULLIF(btrim(p_title), ''), title),
         cover_url = COALESCE(p_cover_url, cover_url),
         updated_at = now()
   WHERE id = p_highlight_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'highlight_not_found_or_not_owner'; END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_story_highlight(uuid, text, text) FROM anon;

CREATE OR REPLACE FUNCTION public.delete_story_highlight(p_highlight_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  DELETE FROM public.story_highlights
   WHERE id = p_highlight_id AND user_id = v_uid;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_story_highlight(uuid) FROM anon;

CREATE OR REPLACE FUNCTION public.add_story_to_highlight(
  p_highlight_id uuid,
  p_story_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pos int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.story_highlights h
                  WHERE h.id = p_highlight_id AND h.user_id = v_uid) THEN
    RAISE EXCEPTION 'highlight_not_found_or_not_owner';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.social_stories s
                  WHERE s.id = p_story_id AND s.user_id = v_uid) THEN
    RAISE EXCEPTION 'story_not_found_or_not_owner';
  END IF;

  SELECT COALESCE(max(position) + 1, 0) INTO v_pos
    FROM public.story_highlight_items WHERE highlight_id = p_highlight_id;

  INSERT INTO public.story_highlight_items (highlight_id, story_id, position)
  VALUES (p_highlight_id, p_story_id, v_pos)
  ON CONFLICT (highlight_id, story_id) DO NOTHING;

  UPDATE public.story_highlights SET updated_at = now() WHERE id = p_highlight_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_story_to_highlight(uuid, uuid) FROM anon;

CREATE OR REPLACE FUNCTION public.remove_story_from_highlight(
  p_highlight_id uuid,
  p_story_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.story_highlights h
                  WHERE h.id = p_highlight_id AND h.user_id = v_uid) THEN
    RAISE EXCEPTION 'highlight_not_found_or_not_owner';
  END IF;
  DELETE FROM public.story_highlight_items
   WHERE highlight_id = p_highlight_id AND story_id = p_story_id;
  UPDATE public.story_highlights SET updated_at = now() WHERE id = p_highlight_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_story_from_highlight(uuid, uuid) FROM anon;

-- Stories inside a highlight (works even for expired stories the owner saved).
CREATE OR REPLACE FUNCTION public.highlight_stories(p_highlight_id uuid)
RETURNS TABLE (
  id            uuid,
  user_id       uuid,
  media_url     text,
  media_type    text,
  caption       text,
  thumbnail_url text,
  created_at    timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, s.user_id, s.media_url, s.media_type, s.caption,
         s.thumbnail_url, s.created_at
    FROM public.story_highlight_items i
    JOIN public.social_stories s ON s.id = i.story_id
   WHERE i.highlight_id = p_highlight_id
   ORDER BY i.position ASC, i.created_at ASC;
$$;

REVOKE EXECUTE ON FUNCTION public.highlight_stories(uuid) FROM anon;

-- ── 5. Realtime for reactions ───────────────────────────────────────────────
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.social_story_reactions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.social_story_reactions REPLICA IDENTITY FULL;
