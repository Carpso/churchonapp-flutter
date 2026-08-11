-- Fix Kids Zone progress tracking.
-- 1) Add the unique constraint that kids_upsert_progress's ON CONFLICT needs.
-- 2) Harden the RPC with an auth.uid() guard (fixes IDOR: any user could
--    previously write arbitrary progress for any user).
-- 3) Add a variant that records completed resource IDs for dedupe.

-- Unique constraint (dedupe: one row per user per week)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'kids_progress_user_week_unique'
  ) THEN
    ALTER TABLE public.kids_progress
      ADD CONSTRAINT kids_progress_user_week_unique UNIQUE (user_id, week_start);
  END IF;
END $$;

-- Hardened RPC: caller must equal the target user.
CREATE OR REPLACE FUNCTION public.kids_upsert_progress(
  p_user_id UUID,
  p_activity_count INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Not allowed to update another user''s progress';
  END IF;
  INSERT INTO public.kids_progress (user_id, points, weekly_activity_count, week_start, updated_at)
  VALUES (p_user_id, p_activity_count * 10, p_activity_count, date_trunc('week', now())::date, now())
  ON CONFLICT (user_id, week_start)
  DO UPDATE SET
    weekly_activity_count = EXCLUDED.weekly_activity_count,
    points = EXCLUDED.points,
    updated_at = now();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.kids_upsert_progress(UUID, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.kids_upsert_progress(UUID, INT) TO authenticated;

-- New RPC: mark a specific resource completed (dedupe-aware).
CREATE OR REPLACE FUNCTION public.kids_mark_resource_completed(
  p_resource_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week DATE := date_trunc('week', now())::date;
BEGIN
  INSERT INTO public.kids_progress (user_id, points, weekly_activity_count, week_start, completed_resource_ids, updated_at)
  VALUES (
    auth.uid(),
    10,
    1,
    v_week,
    ARRAY[p_resource_id],
    now()
  )
  ON CONFLICT (user_id, week_start)
  DO UPDATE SET
    completed_resource_ids = CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM unnest(public.kids_progress.completed_resource_ids) AS rid
        WHERE rid = p_resource_id
      )
      THEN array_append(public.kids_progress.completed_resource_ids, p_resource_id)
      ELSE public.kids_progress.completed_resource_ids
    END,
    weekly_activity_count = (
      SELECT COUNT(*) FROM unnest(
        CASE WHEN public.kids_progress.completed_resource_ids IS NULL
             THEN '{}'::uuid[]::uuid[]
             ELSE public.kids_progress.completed_resource_ids END
      )
    ),
    updated_at = now();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.kids_mark_resource_completed(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.kids_mark_resource_completed(UUID) TO authenticated;
