-- Sermon viewership tracking.
--
-- Audit finding: `sermons.viewer_count` was seeded to 0 and NEVER incremented
-- anywhere in the app, so viewership data was completely dead. This adds a real
-- `sermon_views` log table plus an RPC that logs a view and bumps the counter,
-- deduplicated to one view per user per sermon per 6 hours.

CREATE TABLE IF NOT EXISTS public.sermon_views (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sermon_id       uuid NOT NULL REFERENCES public.sermons(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL,
  watched_seconds integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sermon_views_sermon ON public.sermon_views(sermon_id);
CREATE INDEX IF NOT EXISTS idx_sermon_views_user   ON public.sermon_views(user_id, created_at DESC);

ALTER TABLE public.sermon_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users insert own sermon views" ON public.sermon_views;
CREATE POLICY "Users insert own sermon views" ON public.sermon_views
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read own sermon views" ON public.sermon_views;
CREATE POLICY "Users read own sermon views" ON public.sermon_views
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

GRANT SELECT, INSERT ON public.sermon_views TO authenticated;
REVOKE ALL ON public.sermon_views FROM anon;

-- Record a sermon view + increment the denormalised counter.
CREATE OR REPLACE FUNCTION public.record_sermon_view(p_sermon_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_recent boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_sermon_id IS NULL THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.sermon_views
    WHERE sermon_id = p_sermon_id
      AND user_id = v_uid
      AND created_at > now() - interval '6 hours'
  ) INTO v_recent;

  IF v_recent THEN
    RETURN;
  END IF;

  INSERT INTO public.sermon_views (sermon_id, user_id)
  VALUES (p_sermon_id, v_uid);

  UPDATE public.sermons
     SET viewer_count = COALESCE(viewer_count, 0) + 1
   WHERE id = p_sermon_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_sermon_view(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_sermon_view(uuid) TO authenticated;
