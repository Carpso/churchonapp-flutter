-- ============================================================================
-- 20261261 — TRIAL COST CONTROL (owner decision, 2026-10-31)
--
-- The owner does not want trial streaming to cost much. Two levers:
--   1. HALVE the trial grant 120 -> 60 minutes (one service taster, not two).
--      Delivery cost is minutes x viewers, so this halves the worst-case
--      Cloudflare exposure per trial church. All existing grants are unused
--      (0 minutes consumed - streaming was down), so the backfill is safe.
--   2. Storage is handled in the Edge function: after a successful R2 archive
--      the Cloudflare copy is now DELETED (cloudflare-stream, deployed), so
--      RTMPS recordings stop consuming the $5/1,000-minute storage bucket.
--      Combined, the $5/month Stream subscription covers 100 trial churches.
-- ============================================================================

UPDATE public.platform_settings
   SET value = '60'
 WHERE key = 'streaming_trial_minutes';

UPDATE public.church_stream_config
   SET trial_minutes_total = 60
 WHERE NOT COALESCE(is_paid, false)
   AND COALESCE(trial_minutes_used, 0) = 0
   AND COALESCE(trial_minutes_total, 0) > 60;

-- Verification
DO $$
DECLARE
  v_fail text := '';
BEGIN
  IF COALESCE((SELECT value FROM platform_settings WHERE key = 'streaming_trial_minutes'), '') <> '60' THEN
    v_fail := v_fail || ' settings_key;';
  END IF;
  IF EXISTS (SELECT 1 FROM church_stream_config
              WHERE NOT COALESCE(is_paid, false)
                AND COALESCE(trial_minutes_used, 0) = 0
                AND COALESCE(trial_minutes_total, 0) > 60) THEN
    v_fail := v_fail || ' backfill;';
  END IF;
  IF v_fail <> '' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED:%', v_fail;
  END IF;
  RAISE NOTICE 'trial cost control applied: 60-minute grants';
END;
$$;
