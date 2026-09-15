-- Church social: reposts, real post reporting, and view counts.
--
-- Audit findings: the post "Report" menu item only showed a SnackBar (nothing
-- was stored), there was no repost, and posts had no view count.

-- 1) Repost link + counters on the post itself.
ALTER TABLE public.social_posts
  ADD COLUMN IF NOT EXISTS repost_of   uuid REFERENCES public.social_posts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS repost_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS views_count  integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_social_posts_repost_of ON public.social_posts(repost_of);

-- 2) One view per user per post (so a scroll can't inflate the count).
CREATE TABLE IF NOT EXISTS public.post_views (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    uuid NOT NULL REFERENCES public.social_posts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id)
);

ALTER TABLE public.post_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_views_insert_own" ON public.post_views;
CREATE POLICY "post_views_insert_own" ON public.post_views
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "post_views_select_own" ON public.post_views;
CREATE POLICY "post_views_select_own" ON public.post_views
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
GRANT SELECT, INSERT ON public.post_views TO authenticated;
REVOKE ALL ON public.post_views FROM anon;

-- 3) Reports — the three-dot "Report" previously stored NOTHING.
CREATE TABLE IF NOT EXISTS public.post_reports (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.social_posts(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL,
  reason      text NOT NULL,
  details     text,
  status      text NOT NULL DEFAULT 'open', -- open | reviewing | actioned | dismissed
  reviewed_by uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, reporter_id)
);

CREATE INDEX IF NOT EXISTS idx_post_reports_status ON public.post_reports(status, created_at DESC);
ALTER TABLE public.post_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_reports_insert_own" ON public.post_reports;
CREATE POLICY "post_reports_insert_own" ON public.post_reports
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);

-- Reporters see their own; admins / COA see and triage all.
DROP POLICY IF EXISTS "post_reports_select_own_or_staff" ON public.post_reports;
CREATE POLICY "post_reports_select_own_or_staff" ON public.post_reports
  FOR SELECT TO authenticated USING (
    auth.uid() = reporter_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin','super_admin','coa_employee','employee','admin','pastor','bishop')
    )
  );

DROP POLICY IF EXISTS "post_reports_staff_update" ON public.post_reports;
CREATE POLICY "post_reports_staff_update" ON public.post_reports
  FOR UPDATE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin','super_admin','coa_employee','employee','admin','pastor','bishop')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin','super_admin','coa_employee','employee','admin','pastor','bishop')
    )
  );

GRANT SELECT, INSERT, UPDATE ON public.post_reports TO authenticated;
REVOKE ALL ON public.post_reports FROM anon;

-- 4) RPC: count a view once per user.
CREATE OR REPLACE FUNCTION public.record_post_view(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_inserted boolean := false;
BEGIN
  IF v_uid IS NULL OR p_post_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.post_views (post_id, user_id)
  VALUES (p_post_id, v_uid)
  ON CONFLICT (post_id, user_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted THEN
    UPDATE public.social_posts
       SET views_count = COALESCE(views_count, 0) + 1
     WHERE id = p_post_id;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_post_view(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_post_view(uuid) TO authenticated;

-- 5) RPC: repost (one per user per original post).
CREATE OR REPLACE FUNCTION public.repost_post(p_post_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant    uuid;
  v_original  public.social_posts%ROWTYPE;
  v_existing  uuid;
  v_new_id    uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_original FROM public.social_posts WHERE id = p_post_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Post not found'; END IF;

  -- Cannot repost your own post.
  IF v_original.user_id = v_uid THEN
    RAISE EXCEPTION 'You cannot repost your own post';
  END IF;

  SELECT id INTO v_existing
    FROM public.social_posts
   WHERE repost_of = p_post_id AND user_id = v_uid
   LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT tenant_id::uuid INTO v_tenant FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.social_posts (user_id, content, tenant_id, repost_of)
  VALUES (v_uid, NULL, v_tenant, p_post_id)
  RETURNING id INTO v_new_id;

  UPDATE public.social_posts
     SET repost_count = COALESCE(repost_count, 0) + 1
   WHERE id = p_post_id;

  RETURN v_new_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.repost_post(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.repost_post(uuid) TO authenticated;
