-- Streaming trial: change from 10 min/week to 10 min total
-- Tracks minutes per church per week for analytics,
-- but limit check sums across ALL weeks for trial churches.

-- ============================================================
-- Replace get_streaming_usage
-- ============================================================
DROP FUNCTION IF EXISTS get_streaming_usage(UUID);
CREATE OR REPLACE FUNCTION get_streaming_usage(p_church_id UUID)
RETURNS TABLE(
  minutes_used NUMERIC,
  minutes_limit NUMERIC,
  minutes_remaining NUMERIC,
  can_stream BOOLEAN,
  week_start DATE
) AS $$
DECLARE
  v_week_start DATE;
  v_usage RECORD;
  v_is_trial BOOLEAN;
  v_limit NUMERIC;
  v_total_used NUMERIC;
BEGIN
  v_week_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::INT;

  SELECT subscription_status = 'trial' INTO v_is_trial
  FROM churches WHERE id = p_church_id;

  IF v_is_trial THEN
    v_limit := 10;
    v_total_used := COALESCE(
      (SELECT SUM(minutes_used) FROM streaming_usage WHERE church_id = p_church_id),
      0
    );
  ELSE
    v_limit := -1;
    v_total_used := 0;
  END IF;

  INSERT INTO streaming_usage (church_id, week_start, minutes_limit)
  VALUES (p_church_id, v_week_start, v_limit)
  ON CONFLICT (church_id, week_start) DO UPDATE
  SET minutes_limit = v_limit, updated_at = now()
  RETURNING * INTO v_usage;

  RETURN QUERY SELECT
    COALESCE(v_total_used, v_usage.minutes_used),
    v_usage.minutes_limit,
    CASE WHEN v_usage.minutes_limit = -1 THEN 999999
         ELSE GREATEST(0, v_usage.minutes_limit - COALESCE(v_total_used, v_usage.minutes_used))
    END as minutes_remaining,
    CASE WHEN v_usage.minutes_limit = -1 THEN TRUE
         ELSE COALESCE(v_total_used, v_usage.minutes_used) < v_usage.minutes_limit
    END as can_stream,
    v_week_start;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Replace record_streaming_minutes
-- ============================================================
DROP FUNCTION IF EXISTS record_streaming_minutes(UUID, NUMERIC, INTEGER);
CREATE OR REPLACE FUNCTION record_streaming_minutes(
  p_church_id UUID,
  p_minutes NUMERIC,
  p_peak_viewers INTEGER DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
  v_week_start DATE;
  v_is_trial BOOLEAN;
  v_limit NUMERIC;
  v_total_used NUMERIC;
BEGIN
  v_week_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::INT;

  SELECT subscription_status = 'trial' INTO v_is_trial
  FROM churches WHERE id = p_church_id;

  IF v_is_trial THEN
    v_limit := 10;
    v_total_used := COALESCE(
      (SELECT SUM(minutes_used) FROM streaming_usage WHERE church_id = p_church_id),
      0
    );
  ELSE
    v_limit := -1;
    v_total_used := 0;
  END IF;

  INSERT INTO streaming_usage (church_id, week_start, minutes_used, minutes_limit, stream_count, peak_viewers)
  VALUES (p_church_id, v_week_start, p_minutes, v_limit, 1, p_peak_viewers)
  ON CONFLICT (church_id, week_start) DO UPDATE SET
    minutes_used = streaming_usage.minutes_used + p_minutes,
    stream_count = streaming_usage.stream_count + 1,
    peak_viewers = GREATEST(streaming_usage.peak_viewers, p_peak_viewers),
    updated_at = now();

  RETURN jsonb_build_object(
    'total_minutes_used', COALESCE(v_total_used + p_minutes, p_minutes),
    'minutes_limit', v_limit,
    'can_stream', CASE WHEN v_limit = -1 THEN TRUE
                       ELSE COALESCE(v_total_used + p_minutes, p_minutes) < v_limit
                  END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
