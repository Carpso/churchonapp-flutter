-- Kids Zone progress upsert RPC — marks an activity as completed
-- and increments the weekly counter. Idempotent.
CREATE OR REPLACE FUNCTION public.kids_upsert_progress(
  p_user_id UUID,
  p_activity_count INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
