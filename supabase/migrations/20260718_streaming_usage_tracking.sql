-- Streaming usage tracking for trial limits
-- Tracks minutes used per church per week

CREATE TABLE IF NOT EXISTS streaming_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  week_start DATE NOT NULL, -- Monday of the week
  minutes_used NUMERIC DEFAULT 0,
  minutes_limit NUMERIC DEFAULT 10, -- Trial: 10, Paid: unlimited (-1)
  stream_count INTEGER DEFAULT 0,
  peak_viewers INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(church_id, week_start)
);

-- RLS
ALTER TABLE streaming_usage ENABLE ROW LEVEL SECURITY;

DO $ BEGIN CREATE POLICY "streaming_usage_church" ON streaming_usage; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND church_id = streaming_usage.church_id
    )
  );

DO $ BEGIN CREATE POLICY "streaming_usage_superadmin" ON streaming_usage; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

-- Function to get or create current week usage
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
BEGIN
  -- Get Monday of current week
  v_week_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::INT;

  -- Check if church is on trial
  SELECT subscription_status = 'trial' INTO v_is_trial
  FROM churches WHERE id = p_church_id;

  -- Set limit based on trial status
  IF v_is_trial THEN
    v_limit := 10; -- 10 minutes per week for trial
  ELSE
    v_limit := -1; -- Unlimited for paid
  END IF;

  -- Get or create usage record
  INSERT INTO streaming_usage (church_id, week_start, minutes_limit)
  VALUES (p_church_id, v_week_start, v_limit)
  ON CONFLICT (church_id, week_start) DO UPDATE
  SET minutes_limit = v_limit, updated_at = now()
  RETURNING * INTO v_usage;

  -- Return results
  RETURN QUERY SELECT
    v_usage.minutes_used,
    v_usage.minutes_limit,
    CASE WHEN v_usage.minutes_limit = -1 THEN 999999
         ELSE GREATEST(0, v_usage.minutes_limit - v_usage.minutes_used)
    END as minutes_remaining,
    CASE WHEN v_usage.minutes_limit = -1 THEN TRUE
         ELSE v_usage.minutes_used < v_usage.minutes_limit
    END as can_stream,
    v_week_start;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to record streaming minutes
CREATE OR REPLACE FUNCTION record_streaming_minutes(
  p_church_id UUID,
  p_minutes NUMERIC,
  p_peak_viewers INTEGER DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
  v_week_start DATE;
  v_usage RECORD;
  v_limit NUMERIC;
  v_is_trial BOOLEAN;
BEGIN
  -- Get Monday of current week
  v_week_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::INT;

  -- Check if church is on trial
  SELECT subscription_status = 'trial' INTO v_is_trial
  FROM churches WHERE id = p_church_id;

  -- Set limit
  IF v_is_trial THEN
    v_limit := 10;
  ELSE
    v_limit := -1;
  END IF;

  -- Update usage
  INSERT INTO streaming_usage (church_id, week_start, minutes_used, minutes_limit, stream_count, peak_viewers)
  VALUES (p_church_id, v_week_start, p_minutes, v_limit, 1, p_peak_viewers)
  ON CONFLICT (church_id, v_week_start) DO UPDATE SET
    minutes_used = streaming_usage.minutes_used + p_minutes,
    stream_count = streaming_usage.stream_count + 1,
    peak_viewers = GREATEST(streaming_usage.peak_viewers, p_peak_viewers),
    updated_at = now()
  RETURNING * INTO v_usage;

  RETURN jsonb_build_object(
    'minutes_used', v_usage.minutes_used,
    'minutes_limit', v_usage.minutes_limit,
    'can_stream', CASE WHEN v_usage.minutes_limit = -1 THEN TRUE
                       ELSE v_usage.minutes_used < v_usage.minutes_limit
                  END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
