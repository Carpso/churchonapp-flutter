-- ============================================================================
-- 20261130_pvp_disconnect_pause.sql
-- Disconnect handling for live PvP matches.
--
-- Requirement: if a player goes offline while a match is IN PLAY, the game must
-- automatically PAUSE (not silently lose the opponent), stay resumable for up to
-- 24 hours, and if nobody comes back by then, cancel the match and award the
-- win to the player with the higher score — audited.
--
-- How it works:
--   * Both clients send `pvp_match_heartbeat(match_id)` every ~10s while playing.
--   * A stale heartbeat (> 45s) = disconnected.
--   * `pvp_detect_disconnects()` (cron, every minute) pauses affected matches and
--     sets `resume_deadline = now() + 24h`.
--   * If the player returns and both heartbeats are fresh again, the match
--     auto-resumes on the next heartbeat.
--   * `resolve_expired_pvp_pauses()` (cron) finalises anything past its deadline,
--     sets the winner (higher score; the player who stayed online on a tie) and
--     writes an audit row.
-- ============================================================================

-- 1. Allow the new 'paused' status -------------------------------------------
ALTER TABLE public.pvp_matches DROP CONSTRAINT IF EXISTS pvp_matches_status_check;
ALTER TABLE public.pvp_matches ADD CONSTRAINT pvp_matches_status_check
  CHECK (status IN (
    'pending', 'invited', 'accepted', 'playing', 'paused',
    'completed', 'cancelled', 'declined', 'expired'
  ));

-- 2. Disconnect / resume bookkeeping ----------------------------------------
ALTER TABLE public.pvp_matches
  ADD COLUMN IF NOT EXISTS player1_last_seen timestamptz,
  ADD COLUMN IF NOT EXISTS player2_last_seen timestamptz,
  ADD COLUMN IF NOT EXISTS paused_at         timestamptz,
  ADD COLUMN IF NOT EXISTS resume_deadline   timestamptz,
  ADD COLUMN IF NOT EXISTS ended_reason      text;

CREATE INDEX IF NOT EXISTS idx_pvp_matches_playing
  ON public.pvp_matches (status, created_at)
  WHERE status IN ('playing', 'paused');

-- 3. Audit trail -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pvp_match_audit (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    uuid REFERENCES public.pvp_matches(id) ON DELETE CASCADE,
  event       text NOT NULL,          -- disconnected | resumed | forfeited | cancelled
  actor_id    uuid,
  subject_id  uuid,
  details     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pvp_match_audit_match
  ON public.pvp_match_audit (match_id, created_at DESC);

ALTER TABLE public.pvp_match_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pvp_match_audit_participants_read" ON public.pvp_match_audit;
CREATE POLICY "pvp_match_audit_participants_read"
  ON public.pvp_match_audit FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pvp_matches m
      WHERE m.id = pvp_match_audit.match_id
        AND (m.player1_id = auth.uid() OR m.player2_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- Writes only from the SECURITY DEFINER functions below.
DROP POLICY IF EXISTS "pvp_match_audit_no_client_insert" ON public.pvp_match_audit;

-- 4. Heartbeat ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_match_heartbeat(p_match_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_m      public.pvp_matches%rowtype;
  v_is_p1  boolean;
  v_opp_ok boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_m FROM public.pvp_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF v_m.player1_id <> v_uid AND v_m.player2_id IS DISTINCT FROM v_uid THEN
    RETURN 'forbidden';
  END IF;

  v_is_p1 := (v_m.player1_id = v_uid);

  UPDATE public.pvp_matches
     SET player1_last_seen = CASE WHEN v_is_p1 THEN now() ELSE player1_last_seen END,
         player2_last_seen = CASE WHEN v_is_p1 THEN player2_last_seen ELSE now() END
   WHERE id = p_match_id;

  -- Resume a paused game once BOTH players are heartbeating again.
  IF v_m.status = 'paused' THEN
    v_opp_ok := COALESCE(
      CASE WHEN v_is_p1 THEN v_m.player2_last_seen ELSE v_m.player1_last_seen END,
      to_timestamp(0)
    ) > now() - interval '45 seconds';

    IF v_opp_ok THEN
      UPDATE public.pvp_matches
         SET status = 'playing', paused_at = NULL, resume_deadline = NULL
       WHERE id = p_match_id;

      INSERT INTO public.pvp_match_audit (match_id, event, actor_id, details)
      VALUES (p_match_id, 'resumed', v_uid, jsonb_build_object('at', now()));

      RETURN 'resumed';
    END IF;
    RETURN 'paused';
  END IF;

  RETURN v_m.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.pvp_match_heartbeat(uuid) FROM anon;

-- 5. Detect disconnects (cron) ----------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_detect_disconnects()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row    record;
  v_stale  uuid;
  v_n      int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.pvp_matches
     WHERE status = 'playing'
       AND (
         COALESCE(player1_last_seen, created_at) < now() - interval '45 seconds'
         OR COALESCE(player2_last_seen, created_at) < now() - interval '45 seconds'
       )
  LOOP
    v_stale := CASE
      WHEN COALESCE(v_row.player2_last_seen, v_row.created_at) >
           COALESCE(v_row.player1_last_seen, v_row.created_at)
        THEN v_row.player1_id ELSE v_row.player2_id
    END;

    UPDATE public.pvp_matches
       SET status = 'paused',
           paused_at = now(),
           resume_deadline = now() + interval '24 hours'
     WHERE id = v_row.id;

    INSERT INTO public.pvp_match_audit
      (match_id, event, actor_id, subject_id, details)
    VALUES
      (v_row.id, 'disconnected', NULL, v_stale,
       jsonb_build_object('paused_at', now(),
                          'resume_deadline', now() + interval '24 hours',
                          'player1_score', v_row.player1_score,
                          'player2_score', v_row.player2_score));

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.pvp_detect_disconnects() FROM anon;
REVOKE EXECUTE ON FUNCTION public.pvp_detect_disconnects() FROM authenticated;

-- 6. Resolve expired pauses (cron): cancel + award higher score --------------
CREATE OR REPLACE FUNCTION public.resolve_expired_pvp_pauses()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row    record;
  v_winner uuid;
  v_reason text;
  v_n      int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.pvp_matches
     WHERE status = 'paused'
       AND resume_deadline IS NOT NULL
       AND resume_deadline < now()
     FOR UPDATE SKIP LOCKED
  LOOP
    -- Higher score wins. On a tie, award the player who kept heartbeating
    -- longest (i.e. the one who did not walk away).
    IF COALESCE(v_row.player1_score, 0) > COALESCE(v_row.player2_score, 0) THEN
      v_winner := v_row.player1_id;
    ELSIF COALESCE(v_row.player2_score, 0) > COALESCE(v_row.player1_score, 0) THEN
      v_winner := v_row.player2_id;
    ELSE
      v_winner := CASE
        WHEN COALESCE(v_row.player1_last_seen, v_row.paused_at) >=
             COALESCE(v_row.player2_last_seen, v_row.paused_at)
          THEN v_row.player1_id ELSE v_row.player2_id
      END;
    END IF;

    v_reason := CASE WHEN v_winner = v_row.player1_id
                     THEN 'player2_disconnected_timeout'
                     ELSE 'player1_disconnected_timeout' END;

    UPDATE public.pvp_matches
       SET status = 'cancelled',
           winner_id = v_winner,
           ended_reason = 'opponent_disconnected',
           completed_at = now()
     WHERE id = v_row.id;

    INSERT INTO public.pvp_match_audit
      (match_id, event, actor_id, subject_id, details)
    VALUES
      (v_row.id, 'forfeited', NULL, v_row.player1_id,
       jsonb_build_object(
         'reason', v_reason,
         'winner_id', v_winner,
         'player1_score', v_row.player1_score,
         'player2_score', v_row.player2_score,
         'paused_at', v_row.paused_at,
         'resolved_at', now()));

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.resolve_expired_pvp_pauses() FROM anon;
REVOKE EXECUTE ON FUNCTION public.resolve_expired_pvp_pauses() FROM authenticated;

-- 7. Schedule the sweeps (every minute) -------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('pvp-dc-sweep');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'pvp-dc-sweep',
  '* * * * *',
  $$SELECT public.pvp_detect_disconnects(); SELECT public.resolve_expired_pvp_pauses();$$
);
