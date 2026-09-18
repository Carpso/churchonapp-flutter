-- ============================================================================
-- 20261153_stream_max_quality_paid_baseline.sql
--
-- Paid churches must never be capped below 720p HD. The paid baseline used by
-- `UnifiedStreamService.paidConfig` and the `20261152` platform guard is 1080;
-- AGENTS.md documents `max_quality int -- 720 or 1080`. At least one paid
-- church row carried the legacy trial value 360, which the tenant-facing
-- Streaming Config screen rendered as "Max Quality 360p".
--
-- This corrects any paid row still below 720 and is idempotent — re-running
-- affects 0 rows once fixed.
-- ============================================================================

UPDATE public.church_stream_config
   SET max_quality = 720,
       updated_at  = now()
 WHERE is_paid = true
   AND (max_quality IS NULL OR max_quality < 720);
