-- 20261006: Unlock streaming for paid $5 Cloudflare Stream
-- User subscribed to $5 Stream (2026-09-03). All churches should have
-- generous limits (480 min/week ~8 hrs, 1000 viewers, 90-day retention, 10GB)
-- instead of trial limits (10 min/week, 25 viewers). Also backfill missing
-- configs for 15 tenants that had no row (they fell through to defaultConfig
-- with same trial limits).

-- Upgrade existing trial configs to paid
UPDATE public.church_stream_config
SET is_paid = true,
    max_minutes_per_week = 480,
    max_viewers = 1000,
    retention_days = 90,
    max_storage_gb = 10.0,
    max_stream_duration_sec = 14400,
    max_quality = 1080,
    updated_at = now()
WHERE is_paid = false;

-- Backfill missing configs for churches without a row
INSERT INTO public.church_stream_config (
  church_id, backend, is_paid, max_minutes_per_week, max_viewers,
  retention_days, max_storage_gb, max_stream_duration_sec, max_quality,
  auto_record, enable_chat, enable_prayer_requests, max_concurrent_streams
)
SELECT
  c.id,
  'cloudflare',
  true,
  480,
  1000,
  90,
  10.0,
  14400,
  1080,
  true,
  true,
  true,
  1
FROM public.churches c
LEFT JOIN public.church_stream_config csc ON csc.church_id = c.id
WHERE csc.church_id IS NULL
ON CONFLICT (church_id) DO NOTHING;
