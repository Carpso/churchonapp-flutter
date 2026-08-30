-- =====================================================
-- 20261003 — PvP invite auto-expiry via pg_cron sweep
--
-- Problem: expire_stale_pvp_invites() only expired invites where the current
-- auth.uid() was a participant, so orphaned invites (both players away) stayed
-- 'invited' forever and held the inviter's wager coins.
--
-- Fix: a SECURITY DEFINER global sweep (no auth dependency) + a pg_cron job
-- that runs every 15 minutes, refunding inviters and expiring ANY invite older
-- than the threshold.
-- =====================================================

CREATE OR REPLACE FUNCTION public.expire_all_stale_pvp_invites(
  p_minutes INT DEFAULT 30
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired INT := 0;
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT * FROM pvp_matches
    WHERE status = 'invited'
      AND created_at < now() - make_interval(mins => GREATEST(p_minutes, 1))
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Refund the inviter's wager (mirrors expire_stale_pvp_invites).
    IF v_row.wager_amount > 0 AND v_row.player1_wager_paid_at IS NOT NULL THEN
      UPDATE profiles SET coins = coins + v_row.wager_amount WHERE id = v_row.player1_id;
      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_row.player1_id, v_row.wager_amount, 'pvp_wager_refund', 'Invite expired (cron sweep ' || v_row.id || ')', 'completed');
    END IF;
    UPDATE pvp_matches SET status = 'expired', completed_at = now() WHERE id = v_row.id;
    v_expired := v_expired + 1;
  END LOOP;

  RETURN v_expired;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_all_stale_pvp_invites(INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_all_stale_pvp_invites(INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.expire_all_stale_pvp_invites(INT) TO authenticated;

-- Schedule the sweep every 15 minutes (idempotent: unschedule first).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pvp-invite-expire') THEN
    PERFORM cron.unschedule('pvp-invite-expire');
  END IF;
END $$;

SELECT cron.schedule('pvp-invite-expire', '*/15 * * * *', $$SELECT public.expire_all_stale_pvp_invites(30)$$);