-- Streaming Cost Controls & Storage Gating
-- Cloudflare Stream + R2 only. No Bunny.net.
-- Gates: minutes/week, viewers, retention, storage per tier

-- Add cost control columns to church_stream_config
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS is_paid BOOLEAN DEFAULT false;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS max_minutes_per_week INTEGER DEFAULT 10;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS max_viewers INTEGER DEFAULT 25;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS retention_days INTEGER DEFAULT 7;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS max_storage_gb NUMERIC(5,2) DEFAULT 1.0;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS max_stream_duration_sec INTEGER DEFAULT 3600;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS max_quality INTEGER DEFAULT 720;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS storage_excess_charge_k50 NUMERIC(5,2) DEFAULT 50.0;
ALTER TABLE church_stream_config ADD COLUMN IF NOT EXISTS viewer_overage_charge_k50 NUMERIC(5,2) DEFAULT 5.0;

-- Add storage tracking to live_streams
ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS storage_bytes BIGINT DEFAULT 0;
ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS storage_gb NUMERIC(5,3) GENERATED ALWAYS AS (storage_bytes / 1073741824.0) STORED;

-- Create church_storage_usage table for monthly tracking
CREATE TABLE IF NOT EXISTS church_storage_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  month DATE NOT NULL DEFAULT date_trunc('month', now()),
  storage_gb NUMERIC(5,3) NOT NULL DEFAULT 0,
  excess_gb NUMERIC(5,3) NOT NULL DEFAULT 0,
  excess_charge_k50 NUMERIC(5,2) NOT NULL DEFAULT 0,
  recordings_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(church_id, month)
);

-- Enable RLS
ALTER TABLE church_storage_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Churches can read own storage usage" ON church_storage_usage;
CREATE POLICY "Churches can read own storage usage"
  ON church_storage_usage FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.church_id = church_storage_usage.church_id
    )
  );

DROP POLICY IF EXISTS "System can insert storage usage" ON church_storage_usage;
CREATE POLICY "System can insert storage usage"
  ON church_storage_usage FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "System can update storage usage" ON church_storage_usage;
CREATE POLICY "System can update storage usage"
  ON church_storage_usage FOR UPDATE
  USING (true);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_storage_usage_church ON church_storage_usage(church_id);
CREATE INDEX IF NOT EXISTS idx_storage_usage_month ON church_storage_usage(month);
CREATE INDEX IF NOT EXISTS idx_live_streams_storage ON live_streams(storage_bytes);
CREATE INDEX IF NOT EXISTS idx_live_streams_status ON live_streams(status);

-- Function to get streaming usage (weekly)
DROP FUNCTION IF EXISTS get_streaming_usage(UUID);
CREATE OR REPLACE FUNCTION get_streaming_usage(p_church_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_week_start TIMESTAMPTZ;
  v_minutes_used INTEGER;
  v_minutes_limit INTEGER;
  v_peak_viewers INTEGER;
  v_viewers_limit INTEGER;
  v_storage_used NUMERIC;
  v_storage_limit NUMERIC;
  v_is_paid BOOLEAN;
  v_unlimited BOOLEAN;
BEGIN
  -- Get current week start (Monday)
  v_week_start := date_trunc('week', now());

  -- Get config
  SELECT
    is_paid,
    max_minutes_per_week,
    max_viewers,
    max_storage_gb
  INTO v_is_paid, v_minutes_limit, v_viewers_limit, v_storage_limit
  FROM church_stream_config
  WHERE church_id = p_church_id;

  -- Default to trial limits if no config
  IF v_minutes_limit IS NULL THEN
    v_minutes_limit := 10;
    v_viewers_limit := 25;
    v_storage_limit := 1.0;
    v_is_paid := false;
  END IF;

  -- Calculate minutes used this week
  SELECT COALESCE(SUM(
    EXTRACT(EPOCH FROM (COALESCE(ended_at, now()) - started_at)) / 60
  ), 0)::INTEGER
  INTO v_minutes_used
  FROM live_streams
  WHERE church_id = p_church_id
    AND started_at >= v_week_start
    AND status IN ('live', 'ended');

  -- Get peak viewers
  SELECT COALESCE(MAX(viewer_count), 0)
  INTO v_peak_viewers
  FROM live_streams
  WHERE church_id = p_church_id
    AND started_at >= v_week_start;

  -- Get storage used
  SELECT COALESCE(SUM(storage_bytes), 0) / 1073741824.0
  INTO v_storage_used
  FROM live_streams
  WHERE church_id = p_church_id
    AND status IN ('live', 'ended');

  v_unlimited := v_is_paid AND v_minutes_limit >= 480;

  RETURN jsonb_build_object(
    'church_id', p_church_id,
    'minutes_used', LEAST(v_minutes_used, v_minutes_limit),
    'minutes_limit', v_minutes_limit,
    'peak_viewers', v_peak_viewers,
    'viewers_limit', v_viewers_limit,
    'storage_used_gb', ROUND(v_storage_used, 3),
    'storage_limit_gb', v_storage_limit,
    'is_paid', v_is_paid,
    'unlimited', v_unlimited,
    'can_stream', v_minutes_used < v_minutes_limit,
    'minutes_remaining', GREATEST(v_minutes_limit - v_minutes_used, 0),
    'storage_exceeded', v_storage_used >= v_storage_limit
  );
END;
$$ LANGUAGE plpgsql;

-- Function to record streaming minutes
CREATE OR REPLACE FUNCTION record_streaming_minutes(
  p_church_id UUID,
  p_minutes INTEGER,
  p_peak_viewers INTEGER DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
  v_usage JSONB;
  v_can_stream BOOLEAN;
BEGIN
  -- Check usage first
  v_usage := get_streaming_usage(p_church_id);
  v_can_stream := (v_usage->>'can_stream')::BOOLEAN;

  IF NOT v_can_stream THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Weekly streaming limit reached',
      'usage', v_usage
    );
  END IF;

  -- Record the usage (insert or update)
  INSERT INTO streaming_usage (church_id, week_start, minutes_used, peak_viewers)
  VALUES (p_church_id, date_trunc('week', now()), p_minutes, p_peak_viewers)
  ON CONFLICT (church_id, week_start)
  DO UPDATE SET
    minutes_used = streaming_usage.minutes_used + p_minutes,
    peak_viewers = GREATEST(streaming_usage.peak_viewers, p_peak_viewers),
    updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Usage recorded',
    'usage', get_streaming_usage(p_church_id)
  );
END;
$$ LANGUAGE plpgsql;

-- Function to check and gate streaming
CREATE OR REPLACE FUNCTION check_stream_gate(p_church_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_usage JSONB;
  v_active_streams BIGINT;
  v_storage_exceeded BOOLEAN;
BEGIN
  v_usage := get_streaming_usage(p_church_id);

  -- Check active streams
  SELECT COUNT(*) INTO v_active_streams
  FROM live_streams
  WHERE church_id = p_church_id AND status = 'live';

  v_storage_exceeded := (v_usage->>'storage_exceeded')::BOOLEAN;

  RETURN jsonb_build_object(
    'allowed', (v_usage->>'can_stream')::BOOLEAN AND v_active_streams < 1 AND NOT v_storage_exceeded,
    'reason', CASE
      WHEN NOT (v_usage->>'can_stream')::BOOLEAN THEN 'Weekly limit reached'
      WHEN v_active_streams >= 1 THEN 'Another stream is active'
      WHEN v_storage_exceeded THEN 'Storage limit exceeded — delete old recordings'
      ELSE null
    END,
    'usage', v_usage,
    'active_streams', v_active_streams
  );
END;
$$ LANGUAGE plpgsql;

-- Function to auto-cleanup old recordings (cost control)
CREATE OR REPLACE FUNCTION cleanup_old_recordings(p_church_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_retention_days INTEGER;
  v_deleted INTEGER := 0;
  v_stream RECORD;
BEGIN
  -- Get retention days from config
  SELECT retention_days INTO v_retention_days
  FROM church_stream_config
  WHERE church_id = p_church_id;

  -- Default to 7 days
  IF v_retention_days IS NULL THEN
    v_retention_days := 7;
  END IF;

  -- Find and mark old recordings for deletion
  FOR v_stream IN
    SELECT id, cloudflare_stream_id
    FROM live_streams
    WHERE church_id = p_church_id
      AND status = 'ended'
      AND ended_at < now() - (v_retention_days || ' days')::INTERVAL
      AND cloudflare_stream_id IS NOT NULL
  LOOP
    -- Mark as archived (storage freed, metadata kept)
    UPDATE live_streams
    SET status = 'archived',
        hls_url = null,
        dash_url = null,
        storage_bytes = 0
    WHERE id = v_stream.id;

    v_deleted := v_deleted + 1;
  END LOOP;

  RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate storage excess charge
CREATE OR REPLACE FUNCTION calculate_storage_charge(p_church_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_storage_gb NUMERIC;
  v_free_tier_gb NUMERIC;
  v_excess_gb NUMERIC;
  v_charge_per_gb NUMERIC;
  v_total_charge NUMERIC;
BEGIN
  -- Get total storage
  SELECT COALESCE(SUM(storage_bytes), 0) / 1073741824.0
  INTO v_storage_gb
  FROM live_streams
  WHERE church_id = p_church_id AND status IN ('live', 'ended');

  -- Free tier based on subscription
  SELECT CASE WHEN is_paid THEN 10.0 ELSE 1.0 END
  INTO v_free_tier_gb
  FROM church_stream_config
  WHERE church_id = p_church_id;

  IF v_free_tier_gb IS NULL THEN
    v_free_tier_gb := 1.0;
  END IF;

  v_charge_per_gb := 50.0; -- K50 per GB
  v_excess_gb := GREATEST(v_storage_gb - v_free_tier_gb, 0);
  v_total_charge := v_excess_gb * v_charge_per_gb;

  RETURN jsonb_build_object(
    'storage_gb', ROUND(v_storage_gb, 3),
    'free_tier_gb', v_free_tier_gb,
    'excess_gb', ROUND(v_excess_gb, 3),
    'charge_per_gb_k50', v_charge_per_gb,
    'total_charge_k50', ROUND(v_total_charge, 2)
  );
END;
$$ LANGUAGE plpgsql;

-- Seed default configs for existing churches
INSERT INTO church_stream_config (church_id, backend, is_paid, max_minutes_per_week, max_viewers, retention_days, max_storage_gb, max_stream_duration_sec, max_quality)
SELECT id, 'cloudflare', false, 10, 25, 7, 1.0, 3600, 720
FROM churches
WHERE id NOT IN (SELECT church_id FROM church_stream_config)
ON CONFLICT (church_id) DO NOTHING;
