-- 20260897 Live streaming backend fixes
-- 1) UnifiedStreamService inserts rtmp_url/stream_key/hls_url when creating a
--    Cloudflare (or MediaMTX) live input — those columns never existed, so
--    every "go live" failed at the DB insert. Add them.
ALTER TABLE live_streams
  ADD COLUMN IF NOT EXISTS rtmp_url text,
  ADD COLUMN IF NOT EXISTS stream_key text,
  ADD COLUMN IF NOT EXISTS hls_url text;

-- 2) get_streaming_usage summed a non-existent "minutes" column and checked
--    a non-existent churches.onboarding_fee_paid — every usage check errored
--    and fell back to defaults, silently disabling the weekly-minute gate.
CREATE OR REPLACE FUNCTION public.get_streaming_usage(p_church_id uuid)
 RETURNS TABLE(minutes_used bigint, minutes_limit bigint, minutes_remaining bigint, can_stream boolean, week_start date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_week_start DATE := date_trunc('week', now())::date;
  v_used BIGINT;
  v_limit BIGINT;
BEGIN
  SELECT COALESCE(SUM(su.minutes_used), 0) INTO v_used
  FROM streaming_usage su
  WHERE su.church_id = p_church_id AND su.week_start = v_week_start;

  -- Paid: 480 min/week, Trial/expired: 120 min/week
  IF EXISTS (
    SELECT 1 FROM churches WHERE id = p_church_id
    AND subscription_status = 'paid'
    AND subscription_ends_at > now()
  ) THEN
    v_limit := 480;
  ELSE
    v_limit := 120;
  END IF;

  RETURN QUERY SELECT
    v_used,
    v_limit,
    GREATEST(v_limit - v_used, 0),
    (v_used < v_limit),
    v_week_start;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_streaming_usage(uuid) FROM anon, authenticated;

-- 3) record_streaming_minutes (single overload, uuid + integer + optional
--    peak viewers) — UnifiedStreamService.endStream calls it with 2 args to
--    log weekly usage for the cost-control gate. The old 3-arg variant
--    assigned a TABLE function result to a JSONB variable and crashed.
CREATE OR REPLACE FUNCTION public.record_streaming_minutes(p_church_id uuid, p_minutes integer DEFAULT 0, p_peak_viewers integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO streaming_usage (church_id, week_start, minutes_used, peak_viewers)
  VALUES (p_church_id, date_trunc('week', now())::date, GREATEST(p_minutes, 0), GREATEST(p_peak_viewers, 0))
  ON CONFLICT (church_id, week_start)
  DO UPDATE SET
    minutes_used = streaming_usage.minutes_used + EXCLUDED.minutes_used,
    peak_viewers = GREATEST(streaming_usage.peak_viewers, EXCLUDED.peak_viewers),
    updated_at = now();
  RETURN jsonb_build_object('success', true, 'message', 'Usage recorded');
END;
$function$;

DROP FUNCTION IF EXISTS public.record_streaming_minutes(uuid, numeric);
REVOKE EXECUTE ON FUNCTION public.record_streaming_minutes(uuid, integer, integer) FROM anon, authenticated;