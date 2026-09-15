-- ============================================================================
-- 20261134_social_stories.sql
-- Instagram-style stories for Church Social.
--
--   * A story is a short-lived post (24h default) that shows in a horizontal
--     bar at the top of Connect, with a seen/unseen ring like Instagram.
--   * Stories are tenant-scoped (a member's church) with an optional public
--     flag for the global feed.
--   * Viewing is recorded per viewer (dedup) and drives the seen ring.
--   * Expiry is a timestamp, not a cron: queries filter `expires_at > now()`.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.social_stories (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id     text,
  media_url     text NOT NULL,
  media_type    text NOT NULL DEFAULT 'image',   -- image | video
  thumbnail_url text,
  caption       text,
  background    text,                            -- optional text-story colour
  is_public     boolean NOT NULL DEFAULT false,
  view_count    int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_social_stories_feed
  ON public.social_stories (expires_at DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_social_stories_user
  ON public.social_stories (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.social_story_views (
  story_id  uuid NOT NULL REFERENCES public.social_stories(id) ON DELETE CASCADE,
  viewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS idx_story_views_viewer
  ON public.social_story_views (viewer_id, viewed_at DESC);

ALTER TABLE public.social_stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_story_views ENABLE ROW LEVEL SECURITY;

-- Read: your church's active stories, public ones, and always your own.
DROP POLICY IF EXISTS "social_stories_read" ON public.social_stories;
CREATE POLICY "social_stories_read"
  ON public.social_stories FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      expires_at > now()
      AND (
        is_public = true
        OR tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

DROP POLICY IF EXISTS "social_stories_insert_own" ON public.social_stories;
CREATE POLICY "social_stories_insert_own"
  ON public.social_stories FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "social_stories_delete_own" ON public.social_stories;
CREATE POLICY "social_stories_delete_own"
  ON public.social_stories FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Views: you may record/see only your own view rows (the owner reads counts
-- from `social_stories.view_count`, incremented by the RPC below).
DROP POLICY IF EXISTS "story_views_own" ON public.social_story_views;
CREATE POLICY "story_views_own"
  ON public.social_story_views FOR ALL TO authenticated
  USING (viewer_id = auth.uid())
  WITH CHECK (viewer_id = auth.uid());

-- Owner may see who viewed their story.
DROP POLICY IF EXISTS "story_views_owner_read" ON public.social_story_views;
CREATE POLICY "story_views_owner_read"
  ON public.social_story_views FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.social_stories s
      WHERE s.id = social_story_views.story_id AND s.user_id = auth.uid()
    )
  );

-- ── Record a view (deduped) and bump the counter ────────────────────────────
CREATE OR REPLACE FUNCTION public.record_story_view(p_story_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_inserted boolean := false;
  v_count   int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO public.social_story_views (story_id, viewer_id)
  VALUES (p_story_id, v_uid)
  ON CONFLICT (story_id, viewer_id) DO NOTHING;

  IF FOUND THEN
    UPDATE public.social_stories
       SET view_count = view_count + 1
     WHERE id = p_story_id;
  END IF;

  SELECT view_count INTO v_count FROM public.social_stories WHERE id = p_story_id;
  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_story_view(uuid) FROM anon;

-- ── Realtime so new stories appear without a refresh ────────────────────────
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.social_stories;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.social_stories REPLICA IDENTITY FULL;
