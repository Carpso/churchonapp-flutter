-- =====================================================
-- 20260895: QUIZ SECURITY HARDENING + SERVER-SIDE PvP SETTLEMENT
-- =====================================================
-- Live-audit fixes (2026-08-14):
--   1. 9 SECURITY DEFINER RPCs were PUBLIC EXECUTE — unlimited coin minting
--      (refund_wager_coins), cross-user drain (deduct_wager_coins), replayable
--      ELO/wager farming (calculate_elo_and_award_wager), cross-user answer
--      injection (record_answered_questions / submit_tournament_answers_batch).
--   2. pvp_matches UPDATE policy let any participant write scores + winner
--      (client-trusted). Client can no longer UPDATE pvp_matches at all.
--   3. Player2 never paid the wager at join (two-account infinite mint).
--   4. pvp_answers had no question_id and is_correct was client-trusted;
--      leaderboard counted unverifiable rows.
--   5. daily_challenge_results: client-trusted scores, missing completed_at
--      (leaderboard 42703 → leaderboard silently empty), no dedupe.
--   6. get_unseen_questions: NOT IN subquery + RANDOM() scan, unguarded.
--   7. Event scores written by client via quiz_event_participants UPDATE.
--
-- New model: joins and completions go through SECURITY DEFINER RPCs
-- (join_pvp_match, complete_pvp_match); winners + scores are derived
-- server-side from pvp_answers JOIN quiz_questions; money paths are
-- self-scoped (auth.uid()), capped, replay-guarded and verified against the
-- coin_redemptions ledger.

-- =====================================================
-- 1. Schema additions
-- =====================================================

ALTER TABLE public.pvp_matches
  ADD COLUMN IF NOT EXISTS wager_settled_at TIMESTAMPTZ;

-- question_id links each answer to the bank so correctness can be verified
-- server-side (legacy rows stay NULL and are excluded from scoring).
ALTER TABLE public.pvp_answers
  ADD COLUMN IF NOT EXISTS question_id UUID REFERENCES public.quiz_questions(id) ON DELETE CASCADE;

-- One answer per question per player per match (kills duplicate-insert boosts).
CREATE UNIQUE INDEX IF NOT EXISTS idx_pvp_answers_question_unique
  ON public.pvp_answers (match_id, player_id, question_id)
  WHERE question_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pvp_answers_match_player
  ON public.pvp_answers (match_id, player_id);

-- Matchmaking: pending queue with wager tier + ELO range.
CREATE INDEX IF NOT EXISTS idx_pvp_matches_pending_wager_elo
  ON public.pvp_matches (status, wager_amount, player1_elo_at_match)
  WHERE status = 'pending';

-- Event leaderboards.
CREATE INDEX IF NOT EXISTS idx_quiz_event_participants_event_score
  ON public.quiz_event_participants (event_id, score DESC);

-- daily_challenge_results: completed_at + xp_earned were missing (the
-- 20260893 leaderboard referenced completed_at and errored 42703).
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS xp_earned INT DEFAULT 0;
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_daily_challenge_results_user
  ON public.daily_challenge_results (user_id, created_at DESC);

-- One result per real challenge per user (partial: legacy NULL rows aside).
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_challenge_result_once
  ON public.daily_challenge_results (challenge_id, user_id)
  WHERE challenge_id IS NOT NULL;

-- =====================================================
-- 2. ACL sweep — PUBLIC can no longer execute any quiz RPC
-- =====================================================

REVOKE EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.deduct_wager_coins(UUID, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.refund_wager_coins(UUID, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_unseen_questions(UUID, INT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.count_unseen_questions(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_question_bank_stats() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_unseen_questions(UUID, INT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_unseen_questions(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_question_bank_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) TO authenticated;

-- =====================================================
-- 3. deduct_wager_coins — self-scoped + capped
-- =====================================================

CREATE OR REPLACE FUNCTION public.deduct_wager_coins(
  p_user_id UUID,
  p_amount INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_coins INT;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('error', 'Not authorized');
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000 THEN
    RETURN jsonb_build_object('error', 'Invalid amount');
  END IF;

  SELECT coins INTO v_current_coins FROM profiles WHERE id = p_user_id FOR UPDATE;

  IF v_current_coins IS NULL THEN
    RETURN jsonb_build_object('error', 'User not found');
  END IF;

  IF v_current_coins < p_amount THEN
    RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_current_coins);
  END IF;

  UPDATE profiles SET coins = coins - p_amount WHERE id = p_user_id;

  INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
  VALUES (p_user_id, p_amount, 'pvp_wager', 'PvP wager entry', 'completed');

  RETURN jsonb_build_object('success', true, 'new_balance', v_current_coins - p_amount);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.deduct_wager_coins(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deduct_wager_coins(UUID, INT) TO authenticated;

-- =====================================================
-- 4. refund_wager_coins — self-scoped + ledger-verified (no minting)
-- =====================================================

CREATE OR REPLACE FUNCTION public.refund_wager_coins(
  p_user_id UUID,
  p_amount INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recent_wagers BIGINT;
  v_refunded BIGINT;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('error', 'Not authorized');
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000 THEN
    RETURN jsonb_build_object('error', 'Invalid amount');
  END IF;

  -- Only refund against REAL wager deductions from the last 15 minutes.
  SELECT COALESCE(SUM(amount), 0) INTO v_recent_wagers
  FROM coin_redemptions
  WHERE user_id = p_user_id
    AND redemption_type = 'pvp_wager'
    AND status = 'completed'
    AND created_at > now() - interval '15 minutes';

  SELECT COALESCE(SUM(amount), 0) INTO v_refunded
  FROM coin_redemptions
  WHERE user_id = p_user_id
    AND redemption_type = 'pvp_wager_refund'
    AND status = 'completed'
    AND created_at > now() - interval '15 minutes';

  IF v_recent_wagers - v_refunded < p_amount THEN
    RETURN jsonb_build_object('error', 'Refund exceeds recent wager deductions');
  END IF;

  UPDATE profiles SET coins = coins + p_amount WHERE id = p_user_id;

  INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
  VALUES (p_user_id, p_amount, 'pvp_wager_refund', 'PvP wager refund (queue timeout)', 'completed');

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.refund_wager_coins(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_wager_coins(UUID, INT) TO authenticated;

-- =====================================================
-- 5. calculate_elo_and_award_wager — participant-only, replay-guarded,
--    winner derived server-side from verified answers
-- =====================================================

CREATE OR REPLACE FUNCTION public.calculate_elo_and_award_wager(
  p_match_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match RECORD;
  v_player1 RECORD;
  v_player2 RECORD;
  v_k_factor INT := 32;
  v_expected1 NUMERIC;
  v_expected2 NUMERIC;
  v_actual1 NUMERIC;
  v_actual2 NUMERIC;
  v_new_elo1 INT;
  v_new_elo2 INT;
  v_elo_change1 INT;
  v_elo_change2 INT;
  v_p1_answers BIGINT;
  v_p2_answers BIGINT;
  v_p1_correct BIGINT;
  v_p2_correct BIGINT;
  v_winner_id UUID;
  v_wager_pot INT;
  v_winner_share INT;
  v_burn_share INT;
  v_paid1 BOOLEAN;
  v_paid2 BOOLEAN;
BEGIN
  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF v_match.status != 'completed' OR v_match.completed_at IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not completed');
  END IF;

  -- Replay guard: ELO/wager can only ever settle once.
  IF v_match.wager_settled_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Match already settled');
  END IF;

  -- Caller must be a participant.
  IF auth.uid() IS NULL
     OR (auth.uid() <> v_match.player1_id
         AND (v_match.player2_id IS NULL OR auth.uid() <> v_match.player2_id)) THEN
    RETURN jsonb_build_object('error', 'Not a match participant');
  END IF;

  IF v_match.player2_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No player2 in match');
  END IF;

  -- ---- Server-verified scores (client-written score/winner fields ignored).
  SELECT COUNT(*) INTO v_p1_answers
  FROM pvp_answers WHERE match_id = p_match_id AND player_id = v_match.player1_id;
  SELECT COUNT(*) INTO v_p2_answers
  FROM pvp_answers WHERE match_id = p_match_id AND player_id = v_match.player2_id;

  SELECT COUNT(*) INTO v_p1_correct
  FROM pvp_answers pa
  JOIN quiz_questions qq ON qq.id = pa.question_id
  WHERE pa.match_id = p_match_id
    AND pa.player_id = v_match.player1_id
    AND pa.selected_answer = qq.correct_answer;
  SELECT COUNT(*) INTO v_p2_correct
  FROM pvp_answers pa
  JOIN quiz_questions qq ON qq.id = pa.question_id
  WHERE pa.match_id = p_match_id
    AND pa.player_id = v_match.player2_id
    AND pa.selected_answer = qq.correct_answer;

  IF v_p1_correct > v_p2_correct THEN
    v_winner_id := v_match.player1_id;
  ELSIF v_p2_correct > v_p1_correct THEN
    v_winner_id := v_match.player2_id;
  ELSE
    v_winner_id := NULL; -- draw
  END IF;

  UPDATE pvp_matches SET
    player1_score = v_p1_correct::INT,
    player2_score = v_p2_correct::INT,
    player1_correct = v_p1_correct::INT,
    player2_correct = v_p2_correct::INT,
    winner_id = v_winner_id
  WHERE id = p_match_id;
  v_match.winner_id := v_winner_id;

  -- ---- ELO (unchanged math, server-derived winner).
  SELECT * INTO v_player1 FROM profiles WHERE id = v_match.player1_id FOR UPDATE;
  SELECT * INTO v_player2 FROM profiles WHERE id = v_match.player2_id FOR UPDATE;

  v_expected1 := 1.0 / (1.0 + power(10, (v_player2.elo_rating - v_player1.elo_rating)::NUMERIC / 400));
  v_expected2 := 1.0 - v_expected1;

  IF v_match.winner_id = v_match.player1_id THEN
    v_actual1 := 1.0; v_actual2 := 0.0;
  ELSIF v_match.winner_id = v_match.player2_id THEN
    v_actual1 := 0.0; v_actual2 := 1.0;
  ELSE
    v_actual1 := 0.5; v_actual2 := 0.5;
  END IF;

  v_elo_change1 := ROUND(v_k_factor * (v_actual1 - v_expected1))::INT;
  v_elo_change2 := ROUND(v_k_factor * (v_actual2 - v_expected2))::INT;

  v_new_elo1 := GREATEST(100, v_player1.elo_rating + v_elo_change1);
  v_new_elo2 := GREATEST(100, v_player2.elo_rating + v_elo_change2);

  UPDATE profiles SET
    elo_rating = v_new_elo1,
    highest_elo = GREATEST(highest_elo, v_new_elo1)
  WHERE id = v_match.player1_id;

  UPDATE profiles SET
    elo_rating = v_new_elo2,
    highest_elo = GREATEST(highest_elo, v_new_elo2)
  WHERE id = v_match.player2_id;

  UPDATE pvp_matches SET
    player1_elo_change = v_elo_change1,
    player2_elo_change = v_elo_change2,
    player1_elo_at_match = v_player1.elo_rating,
    player2_elo_at_match = v_player2.elo_rating
  WHERE id = p_match_id;

  -- ---- Wager settlement: only when BOTH players demonstrably paid.
  IF v_match.wager_amount > 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM coin_redemptions
      WHERE user_id = v_match.player1_id
        AND redemption_type = 'pvp_wager'
        AND status = 'completed'
        AND created_at > v_match.created_at - interval '15 minutes'
    ) INTO v_paid1;
    SELECT EXISTS (
      SELECT 1 FROM coin_redemptions
      WHERE user_id = v_match.player2_id
        AND redemption_type = 'pvp_wager'
        AND status = 'completed'
        AND created_at > v_match.created_at - interval '15 minutes'
    ) INTO v_paid2;

    IF v_winner_id IS NOT NULL AND v_paid1 AND v_paid2 THEN
      v_wager_pot := v_match.wager_amount * 2;
      v_winner_share := FLOOR(v_wager_pot * 0.9);
      v_burn_share := v_wager_pot - v_winner_share;

      UPDATE profiles SET coins = coins + v_winner_share WHERE id = v_winner_id;

      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_winner_id, v_winner_share, 'pvp_wager', 'PvP wager win (match: ' || p_match_id || ')', 'completed');

      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_winner_id, v_burn_share, 'pvp_wager_burn', 'Wager burn from match ' || p_match_id, 'completed');
    ELSE
      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_match.player1_id, v_match.wager_amount, 'pvp_wager_void', 'Wager void (unsettled match ' || p_match_id || ')', 'completed');
    END IF;
  END IF;

  UPDATE pvp_matches SET wager_settled_at = now() WHERE id = p_match_id;

  RETURN jsonb_build_object(
    'success', true,
    'winner_id', v_winner_id,
    'player1_elo_change', v_elo_change1,
    'player2_elo_change', v_elo_change2,
    'player1_new_elo', v_new_elo1,
    'player2_new_elo', v_new_elo2,
    'player1_verified_score', v_p1_correct,
    'player2_verified_score', v_p2_correct,
    'wager_settled', v_match.wager_amount > 0
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) TO authenticated;

-- =====================================================
-- 6. join_pvp_match — atomic join: verifies availability, charges the
--    joiner's wager server-side, fills the slot.
-- =====================================================

CREATE OR REPLACE FUNCTION public.join_pvp_match(
  p_match_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_match RECORD;
  v_coins INT;
  v_p2_elo INT;
  v_same_tenant BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF v_match.status <> 'pending' OR v_match.player2_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Match no longer available');
  END IF;

  IF v_match.created_at < now() - interval '10 minutes' THEN
    RETURN jsonb_build_object('error', 'Match expired');
  END IF;

  IF v_match.player1_id = v_uid THEN
    RETURN jsonb_build_object('error', 'Cannot join your own match');
  END IF;

  -- Player2 pays the wager server-side (closes the two-account mint).
  IF v_match.wager_amount > 0 THEN
    SELECT coins INTO v_coins FROM profiles WHERE id = v_uid FOR UPDATE;
    IF v_coins IS NULL THEN
      RETURN jsonb_build_object('error', 'User not found');
    END IF;
    IF v_coins < v_match.wager_amount THEN
      RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_coins);
    END IF;

    UPDATE profiles SET coins = coins - v_match.wager_amount WHERE id = v_uid;

    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_uid, v_match.wager_amount, 'pvp_wager', 'PvP wager entry', 'completed');
  END IF;

  SELECT elo_rating INTO v_p2_elo FROM profiles WHERE id = v_uid;

  SELECT EXISTS (
    SELECT 1 FROM profiles p1
    WHERE p1.id = v_match.player1_id
      AND p1.tenant_id IS NOT DISTINCT FROM (
        SELECT tenant_id FROM profiles WHERE id = v_uid
      )
  ) INTO v_same_tenant;

  UPDATE pvp_matches SET
    player2_id = v_uid,
    status = 'accepted',
    channel_name = 'pvp_' || p_match_id::text,
    cross_tenant = NOT COALESCE(v_same_tenant, false),
    player2_elo_at_match = v_p2_elo
  WHERE id = p_match_id;

  RETURN jsonb_build_object('success', true, 'match_id', p_match_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.join_pvp_match(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_pvp_match(UUID) TO authenticated;

-- =====================================================
-- 7. complete_pvp_match — idempotent completion; winner + settlement are
--    derived server-side by calculate_elo_and_award_wager.
-- =====================================================

CREATE OR REPLACE FUNCTION public.complete_pvp_match(
  p_match_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF auth.uid() IS NULL
     OR (auth.uid() <> v_match.player1_id
         AND (v_match.player2_id IS NULL OR auth.uid() <> v_match.player2_id)) THEN
    RETURN jsonb_build_object('error', 'Not a match participant');
  END IF;

  -- Idempotent: already settled → return current state (no double ELO/wager).
  IF v_match.wager_settled_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_settled', true,
      'winner_id', v_match.winner_id,
      'player1_elo_change', v_match.player1_elo_change,
      'player2_elo_change', v_match.player2_elo_change
    );
  END IF;

  UPDATE pvp_matches SET status = 'completed', completed_at = now()
  WHERE id = p_match_id;

  v_result := public.calculate_elo_and_award_wager(p_match_id);

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.complete_pvp_match(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_pvp_match(UUID) TO authenticated;

-- =====================================================
-- 8. pvp_matches RLS — no more client UPDATEs (scores/status/winners are
--    server-side now). INSERT (host creates pending match) + SELECT stay.
-- =====================================================

DROP POLICY IF EXISTS "pvp_matches_update_players" ON public.pvp_matches;

-- Older-named duplicates created by the missing-tables migration batch:
-- the UPDATE policy lets any participant write scores/winner (client-trusted
-- hole) and the INSERT policy allowed question_id-less self-boosting rows.
DROP POLICY IF EXISTS "Players can update own matches" ON public.pvp_matches;
DROP POLICY IF EXISTS "Players can insert own answers" ON public.pvp_answers;

-- =====================================================
-- 9. pvp_answers RLS — must reference a real question in a live match you
--    are part of. (Correctness is verified server-side at settlement.)
-- =====================================================

DROP POLICY IF EXISTS "pvp_answers_insert_auth" ON public.pvp_answers;
CREATE POLICY "pvp_answers_insert_auth"
  ON public.pvp_answers FOR INSERT TO authenticated
  WITH CHECK (
    player_id = auth.uid()
    AND question_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.pvp_matches m
      WHERE m.id = match_id
        AND m.status IN ('accepted', 'playing', 'completed')
        AND (m.player1_id = auth.uid() OR m.player2_id = auth.uid())
    )
  );

-- =====================================================
-- 10. record_answered_questions — self-scoped, capped, server-verified.
--     Signature extended with p_answers (correctness derived from the bank).
-- =====================================================

DROP FUNCTION IF EXISTS public.record_answered_questions(UUID, UUID[], UUID, UUID, BOOLEAN[], INT[]);

CREATE OR REPLACE FUNCTION public.record_answered_questions(
  p_user_id UUID,
  p_question_ids UUID[],
  p_match_id UUID DEFAULT NULL,
  p_event_id UUID DEFAULT NULL,
  p_is_correct BOOLEAN[] DEFAULT NULL,
  p_response_times_ms INT[] DEFAULT NULL,
  p_answers INT[] DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INT := 0;
  i INT;
  v_correct_answer INT;
  v_verified BOOLEAN;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN 0;
  END IF;

  IF p_question_ids IS NULL OR array_length(p_question_ids, 1) = 0 THEN
    RETURN 0;
  END IF;

  IF array_length(p_question_ids, 1) > 100 THEN
    RETURN 0;
  END IF;

  FOR i IN 1..array_length(p_question_ids, 1) LOOP
    SELECT correct_answer INTO v_correct_answer
    FROM public.quiz_questions WHERE id = p_question_ids[i];

    IF v_correct_answer IS NULL THEN
      CONTINUE;
    END IF;

    -- Server-verified correctness when answers are supplied; otherwise fall
    -- back to the client flag (keeps pre-fix callers working).
    IF p_answers IS NOT NULL AND i <= array_length(p_answers, 1) THEN
      v_verified := p_answers[i] = v_correct_answer;
    ELSE
      v_verified := COALESCE(p_is_correct[i], false);
    END IF;

    INSERT INTO public.user_answered_questions (
      user_id, question_id, match_id, event_id, is_correct, response_time_ms
    ) VALUES (
      p_user_id,
      p_question_ids[i],
      p_match_id,
      p_event_id,
      v_verified,
      COALESCE(p_response_times_ms[i], 0)
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  RETURN v_inserted;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_answered_questions(UUID, UUID[], UUID, UUID, BOOLEAN[], INT[], INT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_answered_questions(UUID, UUID[], UUID, UUID, BOOLEAN[], INT[], INT[]) TO authenticated;

-- =====================================================
-- 11. submit_tournament_answers_batch — self-scoped, capped, must be a
--     participant. (Answers already verified against the bank.)
-- =====================================================

CREATE OR REPLACE FUNCTION public.submit_tournament_answers_batch(
  p_user_id UUID,
  p_event_id UUID,
  p_question_ids UUID[],
  p_answers INT[],
  p_response_times_ms INT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score INT := 0;
  v_correct INT := 0;
  v_total INT;
  i INT;
  v_question RECORD;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('error', 'Not authorized');
  END IF;

  IF p_question_ids IS NULL OR array_length(p_question_ids, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No questions');
  END IF;

  IF array_length(p_question_ids, 1) > 200 THEN
    RETURN jsonb_build_object('error', 'Too many questions');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE event_id = p_event_id AND user_id = p_user_id
  ) THEN
    RETURN jsonb_build_object('error', 'Not an event participant');
  END IF;

  v_total := array_length(p_question_ids, 1);

  FOR i IN 1..v_total LOOP
    SELECT * INTO v_question
    FROM public.quiz_questions
    WHERE id = p_question_ids[i];

    IF v_question IS NULL THEN
      CONTINUE;
    END IF;

    IF p_answers[i] = v_question.correct_answer THEN
      v_correct := v_correct + 1;
      v_score := v_score + v_question.points;
    END IF;

    INSERT INTO public.user_answered_questions (
      user_id, question_id, event_id, is_correct, response_time_ms
    ) VALUES (
      p_user_id,
      p_question_ids[i],
      p_event_id,
      p_answers[i] = v_question.correct_answer,
      COALESCE(p_response_times_ms[i], 0)
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  UPDATE public.quiz_event_participants
  SET score = v_score,
      correct_count = v_correct,
      total_questions = v_total,
      completed_at = now()
  WHERE event_id = p_event_id AND user_id = p_user_id;

  RETURN jsonb_build_object(
    'score', v_score,
    'correct', v_correct,
    'total', v_total,
    'accuracy', CASE WHEN v_total > 0 THEN ROUND(v_correct::NUMERIC / v_total, 2) ELSE 0 END
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.submit_tournament_answers_batch(UUID, UUID, UUID[], INT[], INT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_tournament_answers_batch(UUID, UUID, UUID[], INT[], INT[]) TO authenticated;

-- Client can no longer write scores to event participants (verified RPC only).
DROP POLICY IF EXISTS "quiz_event_participants_update_own" ON public.quiz_event_participants;

-- =====================================================
-- 12. get_unseen_questions / count_unseen_questions — self-scoped + NOT EXISTS
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_unseen_questions(
  p_user_id UUID,
  p_count INT DEFAULT 10,
  p_category TEXT DEFAULT NULL,
  p_difficulty TEXT DEFAULT NULL,
  p_exclude_superadmin BOOLEAN DEFAULT true
)
RETURNS SETOF public.quiz_questions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RETURN QUERY SELECT * FROM public.quiz_questions WHERE false;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT q.*
  FROM public.quiz_questions q
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.user_answered_questions ua
    WHERE ua.user_id = p_user_id AND ua.question_id = q.id
  )
  AND (p_exclude_superadmin = false OR q.is_superadmin_only = false)
  AND (p_category IS NULL OR q.category = p_category)
  AND (p_difficulty IS NULL OR q.difficulty = p_difficulty)
  ORDER BY RANDOM()
  LIMIT p_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_unseen_questions(UUID, INT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_unseen_questions(UUID, INT, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.count_unseen_questions(
  p_user_id UUID,
  p_category TEXT DEFAULT NULL,
  p_difficulty TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.quiz_questions q
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.user_answered_questions ua
    WHERE ua.user_id = p_user_id AND ua.question_id = q.id
  )
  AND q.is_superadmin_only = false
  AND (p_category IS NULL OR q.category = p_category)
  AND (p_difficulty IS NULL OR q.difficulty = p_difficulty);

  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.count_unseen_questions(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.count_unseen_questions(UUID, TEXT, TEXT) TO authenticated;

-- =====================================================
-- 13. get_quiz_leaderboard — correctness verified against the question bank,
--     p_limit capped.
-- =====================================================

DROP FUNCTION IF EXISTS public.get_quiz_leaderboard(INT, UUID);

CREATE OR REPLACE FUNCTION public.get_quiz_leaderboard(
  p_limit INT DEFAULT 10,
  p_tenant_id UUID DEFAULT NULL,
  p_since TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  correct_answers BIGINT,
  games_played BIGINT,
  best_accuracy NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH pvp AS (
    SELECT pa.player_id AS uid,
           COUNT(*) FILTER (WHERE qq.correct_answer IS NOT NULL AND pa.selected_answer = qq.correct_answer) AS correct,
           COUNT(DISTINCT pa.match_id) AS games
    FROM public.pvp_answers pa
    LEFT JOIN public.quiz_questions qq ON qq.id = pa.question_id
    WHERE (p_since IS NULL OR pa.created_at >= p_since)
    GROUP BY pa.player_id
  ),
  challenge AS (
    SELECT dc.user_id AS uid,
           COALESCE(SUM(dc.correct_count), 0)::BIGINT AS correct,
           COUNT(*) AS games
    FROM public.daily_challenge_results dc
    WHERE (p_since IS NULL OR dc.completed_at >= p_since)
    GROUP BY dc.user_id
  ),
  merged AS (
    SELECT uid, correct, games FROM pvp
    UNION ALL
    SELECT uid, correct, games FROM challenge
  ),
  totals AS (
    SELECT uid, SUM(correct)::BIGINT AS total_correct, SUM(games)::BIGINT AS total_games
    FROM merged
    GROUP BY uid
  )
  SELECT
    t.uid,
    COALESCE(p.full_name, 'Quiz Player')::TEXT AS full_name,
    COALESCE(t.total_correct, 0)::BIGINT AS correct_answers,
    COALESCE(t.total_games, 0)::BIGINT AS games_played,
    CASE WHEN t.total_games > 0
         THEN ROUND(t.total_correct::NUMERIC / t.total_games * 100, 1)
         ELSE 0 END AS best_accuracy
  FROM totals t
  LEFT JOIN public.profiles p ON p.id = t.uid
  WHERE (p_tenant_id IS NULL OR p.tenant_id::text = p_tenant_id::text)
  ORDER BY correct_answers DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 100);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) TO authenticated;

-- =====================================================
-- 14. submit_daily_challenge_result — server-verified daily challenge
--     submission (score derived from the bank; one per day per user).
-- =====================================================

CREATE OR REPLACE FUNCTION public.submit_daily_challenge_result(
  p_challenge_id TEXT DEFAULT NULL,
  p_question_ids UUID[] DEFAULT NULL,
  p_answers INT[] DEFAULT NULL,
  p_response_times_ms INT[] DEFAULT NULL,
  p_xp_earned INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_challenge_uuid UUID;
  v_score INT := 0;
  v_correct INT := 0;
  v_total INT;
  i INT;
  v_correct_answer INT;
  v_points INT;
  v_xp INT;
  v_inserted INT := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_question_ids IS NULL OR array_length(p_question_ids, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No questions');
  END IF;

  IF array_length(p_question_ids, 1) > 100 THEN
    RETURN jsonb_build_object('error', 'Too many questions');
  END IF;

  -- challenge_id may be a synthetic id ('daily_YYYY-MM-DD') → keep NULL.
  IF p_challenge_id IS NOT NULL THEN
    BEGIN
      v_challenge_uuid := p_challenge_id::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_challenge_uuid := NULL;
    END;
  END IF;

  -- One completion per calendar day per user.
  IF EXISTS (
    SELECT 1 FROM public.daily_challenge_results
    WHERE user_id = v_uid
      AND completed_at >= date_trunc('day', now())
  ) THEN
    RETURN jsonb_build_object('error', 'Already completed today');
  END IF;

  v_total := array_length(p_question_ids, 1);
  v_xp := LEAST(GREATEST(p_xp_earned, 0), 100);

  FOR i IN 1..v_total LOOP
    SELECT correct_answer, points INTO v_correct_answer, v_points
    FROM public.quiz_questions WHERE id = p_question_ids[i];

    IF v_correct_answer IS NULL THEN
      CONTINUE;
    END IF;

    IF p_answers IS NOT NULL AND i <= array_length(p_answers, 1)
       AND p_answers[i] = v_correct_answer THEN
      v_correct := v_correct + 1;
      v_score := v_score + COALESCE(v_points, 10);
    END IF;
  END LOOP;

  INSERT INTO public.daily_challenge_results (
    challenge_id, user_id, score, correct_count, total_questions,
    xp_earned, is_correct, completed_at
  ) VALUES (
    v_challenge_uuid, v_uid, v_score, v_correct, v_total,
    v_xp, v_correct = v_total, now()
  )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN jsonb_build_object('error', 'Already completed today');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'score', v_score,
    'correct', v_correct,
    'total', v_total
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.submit_daily_challenge_result(TEXT, UUID[], INT[], INT[], INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_daily_challenge_result(TEXT, UUID[], INT[], INT[], INT) TO authenticated;

-- =====================================================
-- 15. Belt & suspenders — no anon EXECUTE on any quiz RPC (Supabase default
--     privileges grant anon directly on new functions).
-- =====================================================

REVOKE EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.deduct_wager_coins(UUID, INT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.refund_wager_coins(UUID, INT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_answered_questions(UUID, UUID[], UUID, UUID, BOOLEAN[], INT[], INT[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.submit_tournament_answers_batch(UUID, UUID, UUID[], INT[], INT[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_unseen_questions(UUID, INT, TEXT, TEXT, BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.count_unseen_questions(UUID, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_question_bank_stats() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) FROM anon;
REVOKE EXECUTE ON FUNCTION public.join_pvp_match(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.complete_pvp_match(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.submit_daily_challenge_result(TEXT, UUID[], INT[], INT[], INT) FROM anon;
