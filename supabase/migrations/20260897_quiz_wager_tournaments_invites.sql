-- 20260897 Quiz wager tournaments + friend invites (free/paid 1v1)
-- Every participant stakes `wager_coins` at join; winners paid 1st/2nd/3rd
-- (50/30/20 of pot, 2-player winner-takes-all, 1-player/no-show refunds).
-- Friend invites: create/accept/decline/expire with wager charged server-side
-- at stake time (paid_at columns make settlement coverage invite-proof).

-- =====================================================
-- 1. Schema
-- =====================================================

ALTER TABLE public.pvp_matches
  ADD COLUMN IF NOT EXISTS player1_wager_paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS player2_wager_paid_at TIMESTAMPTZ;

ALTER TABLE public.quiz_events
  ADD COLUMN IF NOT EXISTS wager_coins INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;

-- =====================================================
-- 2. join_pvp_match — record player2's payment time (invite-proof coverage).
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
    player2_elo_at_match = v_p2_elo,
    player2_wager_paid_at = CASE WHEN v_match.wager_amount > 0 THEN now() ELSE NULL END
  WHERE id = p_match_id;

  RETURN jsonb_build_object('success', true, 'match_id', p_match_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.join_pvp_match(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_pvp_match(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_pvp_match(UUID) TO authenticated;

-- =====================================================
-- 3. calculate_elo_and_award_wager — paid_at-aware coverage + fair refunds
--    (draw or partial coverage refunds everyone who demonstrably paid).
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

  -- ---- Wager settlement: paid_at column (invite-proof) OR legacy window.
  IF v_match.wager_amount > 0 THEN
    v_paid1 := v_match.player1_wager_paid_at IS NOT NULL OR EXISTS (
      SELECT 1 FROM coin_redemptions
      WHERE user_id = v_match.player1_id
        AND redemption_type = 'pvp_wager'
        AND status = 'completed'
        AND created_at > v_match.created_at - interval '15 minutes'
    );
    v_paid2 := v_match.player2_wager_paid_at IS NOT NULL OR EXISTS (
      SELECT 1 FROM coin_redemptions
      WHERE user_id = v_match.player2_id
        AND redemption_type = 'pvp_wager'
        AND status = 'completed'
        AND created_at > v_match.created_at - interval '15 minutes'
    );

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
      -- Draw or incomplete coverage → refund every player who demonstrably paid.
      IF v_paid1 THEN
        UPDATE profiles SET coins = coins + v_match.wager_amount WHERE id = v_match.player1_id;
        INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
        VALUES (v_match.player1_id, v_match.wager_amount, 'pvp_wager_refund', 'Wager refund (match ' || p_match_id || ')', 'completed');
      END IF;
      IF v_paid2 THEN
        UPDATE profiles SET coins = coins + v_match.wager_amount WHERE id = v_match.player2_id;
        INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
        VALUES (v_match.player2_id, v_match.wager_amount, 'pvp_wager_refund', 'Wager refund (match ' || p_match_id || ')', 'completed');
      END IF;
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
REVOKE EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.calculate_elo_and_award_wager(UUID) TO authenticated;

-- =====================================================
-- 4. Friend invite RPCs (free or paid, chosen by the inviter).
-- =====================================================

-- Inviter creates the match (status 'invited'); wager is charged immediately.
CREATE OR REPLACE FUNCTION public.create_pvp_invite(
  p_opponent_id UUID,
  p_wager_coins INT DEFAULT 0,
  p_question_count INT DEFAULT 10,
  p_time_per_question INT DEFAULT 15
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_coins INT;
  v_elo INT;
  v_tid TEXT;
  v_match_id UUID := gen_random_uuid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_opponent_id IS NULL OR p_opponent_id = v_uid THEN
    RETURN jsonb_build_object('error', 'Invalid opponent');
  END IF;

  IF p_wager_coins < 0 OR p_wager_coins > 1000 THEN
    RETURN jsonb_build_object('error', 'Wager must be between 0 and 1000 CC');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_opponent_id) THEN
    RETURN jsonb_build_object('error', 'Opponent not found');
  END IF;

  SELECT coins, elo_rating, tenant_id INTO v_coins, v_elo, v_tid
  FROM profiles WHERE id = v_uid;

  -- Charge the inviter now (server-side, atomic).
  IF p_wager_coins > 0 THEN
    IF v_coins < p_wager_coins THEN
      RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_coins);
    END IF;
    UPDATE profiles SET coins = coins - p_wager_coins WHERE id = v_uid;
    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_uid, p_wager_coins, 'pvp_wager', 'PvP invite wager entry', 'completed');
  END IF;

  INSERT INTO pvp_matches (
    id, player1_id, player2_id, status, channel_name,
    question_count, time_per_question, wager_amount,
    player1_elo_at_match, tenant_id,
    player1_wager_paid_at
  ) VALUES (
    v_match_id, v_uid, p_opponent_id, 'invited', 'pvp_' || v_match_id::text,
    GREATEST(LEAST(p_question_count, 30), 5), GREATEST(LEAST(p_time_per_question, 30), 5),
    p_wager_coins, v_elo, v_tid,
    CASE WHEN p_wager_coins > 0 THEN now() ELSE NULL END
  );

  RETURN jsonb_build_object(
    'success', true,
    'match_id', v_match_id,
    'status', 'invited',
    'wager_amount', p_wager_coins
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_pvp_invite(UUID, INT, INT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_pvp_invite(UUID, INT, INT, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pvp_invite(UUID, INT, INT, INT) TO authenticated;

-- Opponent accepts; their wager is charged at acceptance.
CREATE OR REPLACE FUNCTION public.accept_pvp_invite(
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
  v_elo INT;
  v_same_tenant BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF v_match.status <> 'invited' THEN
    RETURN jsonb_build_object('error', 'Invite no longer active');
  END IF;

  IF v_match.player2_id <> v_uid THEN
    RETURN jsonb_build_object('error', 'This invite is not for you');
  END IF;

  IF v_match.created_at < now() - interval '30 minutes' THEN
    RETURN jsonb_build_object('error', 'Invite expired');
  END IF;

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
    VALUES (v_uid, v_match.wager_amount, 'pvp_wager', 'PvP invite wager entry', 'completed');
  END IF;

  SELECT elo_rating INTO v_elo FROM profiles WHERE id = v_uid;

  SELECT EXISTS (
    SELECT 1 FROM profiles p1
    WHERE p1.id = v_match.player1_id
      AND p1.tenant_id IS NOT DISTINCT FROM (
        SELECT tenant_id FROM profiles WHERE id = v_uid
      )
  ) INTO v_same_tenant;

  UPDATE pvp_matches SET
    status = 'accepted',
    channel_name = 'pvp_' || p_match_id::text,
    cross_tenant = NOT COALESCE(v_same_tenant, false),
    player2_elo_at_match = v_elo,
    player2_wager_paid_at = CASE WHEN v_match.wager_amount > 0 THEN now() ELSE NULL END
  WHERE id = p_match_id;

  RETURN jsonb_build_object('success', true, 'match_id', p_match_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.accept_pvp_invite(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_pvp_invite(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.accept_pvp_invite(UUID) TO authenticated;

-- Opponent declines; the inviter is refunded.
CREATE OR REPLACE FUNCTION public.decline_pvp_invite(
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF v_match.status <> 'invited' THEN
    RETURN jsonb_build_object('error', 'Invite no longer active');
  END IF;

  IF v_match.player2_id <> v_uid THEN
    RETURN jsonb_build_object('error', 'This invite is not for you');
  END IF;

  -- Refund the inviter (paid at creation).
  IF v_match.wager_amount > 0 AND v_match.player1_wager_paid_at IS NOT NULL THEN
    UPDATE profiles SET coins = coins + v_match.wager_amount WHERE id = v_match.player1_id;
    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_match.player1_id, v_match.wager_amount, 'pvp_wager_refund', 'Invite declined (match ' || p_match_id || ')', 'completed');
  END IF;

  UPDATE pvp_matches SET status = 'declined', completed_at = now()
  WHERE id = p_match_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.decline_pvp_invite(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.decline_pvp_invite(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.decline_pvp_invite(UUID) TO authenticated;

-- Sweep stale invites (default 30 min) — refunds the inviter.
CREATE OR REPLACE FUNCTION public.expire_stale_pvp_invites(
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
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT * FROM pvp_matches
    WHERE status = 'invited'
      AND (player2_id = auth.uid() OR player1_id = auth.uid())
      AND created_at < now() - make_interval(mins => GREATEST(p_minutes, 1))
    FOR UPDATE
  LOOP
    IF v_row.wager_amount > 0 AND v_row.player1_wager_paid_at IS NOT NULL THEN
      UPDATE profiles SET coins = coins + v_row.wager_amount WHERE id = v_row.player1_id;
      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_row.player1_id, v_row.wager_amount, 'pvp_wager_refund', 'Invite expired (match ' || v_row.id || ')', 'completed');
    END IF;
    UPDATE pvp_matches SET status = 'expired', completed_at = now() WHERE id = v_row.id;
    v_expired := v_expired + 1;
  END LOOP;

  RETURN v_expired;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.expire_stale_pvp_invites(INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_stale_pvp_invites(INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.expire_stale_pvp_invites(INT) TO authenticated;

-- =====================================================
-- 5. Wager tournaments (quiz_events.wager_coins).
-- =====================================================

-- join_quiz_event — now also stakes the event wager server-side.
CREATE OR REPLACE FUNCTION public.join_quiz_event(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event RECORD;
  v_count INT;
  v_paid BOOLEAN;
  v_coins INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT status, pass_price, max_participants, wager_coins
    INTO v_event
    FROM public.quiz_events
   WHERE id = p_event_id
   LIMIT 1;

  IF v_event.status IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  IF v_event.status NOT IN ('upcoming', 'active') THEN
    RETURN jsonb_build_object('error', 'Event is not open for joining');
  END IF;

  -- Already a participant? Idempotent rejoin.
  IF EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE user_id = v_uid AND event_id = p_event_id
  ) THEN
    RETURN jsonb_build_object('success', true, 'already_joined', true);
  END IF;

  -- Paid-pass events require a confirmed pass before joining.
  IF COALESCE(v_event.pass_price, 0) > 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM public.quiz_passes
      WHERE event_id = p_event_id AND user_id = v_uid AND status = 'paid'
    ) INTO v_paid;
    IF NOT COALESCE(v_paid, false) THEN
      RETURN jsonb_build_object('error', 'Paid pass required');
    END IF;
  END IF;

  -- Cap enforcement (default 100 like the schema default).
  SELECT count(*) INTO v_count
    FROM public.quiz_event_participants
   WHERE event_id = p_event_id;

  IF v_count >= COALESCE(v_event.max_participants, 100) THEN
    RETURN jsonb_build_object('error', 'Event is full');
  END IF;

  -- Wager tournaments: every participant stakes server-side at join.
  IF COALESCE(v_event.wager_coins, 0) > 0 THEN
    SELECT coins INTO v_coins FROM profiles WHERE id = v_uid FOR UPDATE;
    IF v_coins IS NULL THEN
      RETURN jsonb_build_object('error', 'User not found');
    END IF;
    IF v_coins < v_event.wager_coins THEN
      RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_coins);
    END IF;

    UPDATE profiles SET coins = coins - v_event.wager_coins WHERE id = v_uid;

    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_uid, v_event.wager_coins, 'quiz_tournament_wager',
            'Tournament wager entry (event: ' || p_event_id || ')', 'completed');
  END IF;

  INSERT INTO public.quiz_event_participants (event_id, user_id)
  VALUES (p_event_id, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('success', true, 'joined', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_quiz_event(UUID) TO authenticated;

-- Host/admin finishes the event: ranks players and pays 1st/2nd/3rd.
--   players == 1        → refund
--   players == 2        → winner takes the pot
--   players >= 3        → 1st 50% / 2nd 30% / 3rd 20% of the pot
--   no-shows (no answers) → wager refunded
CREATE OR REPLACE FUNCTION public.complete_quiz_event(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event RECORD;
  v_paid_rows INT;
  v_wager INT;
  v_players INT := 0;
  v_pot INT;
  v_ranked RECORD;
  v_share INT;
  v_remaining INT;
  v_place INT;
  v_payouts JSONB := '[]'::jsonb;
  v_rank INT := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_event FROM public.quiz_events WHERE id = p_event_id FOR UPDATE;

  IF v_event IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  -- Host or platform staff only.
  IF v_event.created_by <> v_uid
     AND NOT EXISTS (
       SELECT 1 FROM profiles
       WHERE id = v_uid AND role IN ('superadmin', 'employee', 'coa_employee')
     ) THEN
    RETURN jsonb_build_object('error', 'Only the host can finish this event');
  END IF;

  IF v_event.settled_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Event already settled');
  END IF;

  IF v_event.status NOT IN ('active', 'upcoming') THEN
    RETURN jsonb_build_object('error', 'Event cannot be finished from this state');
  END IF;

  v_wager := COALESCE(v_event.wager_coins, 0);

  IF v_wager > 0 THEN
    -- Refund no-shows (joined but never submitted a score).
    UPDATE profiles SET coins = coins + v_wager
    FROM quiz_event_participants p
    WHERE p.event_id = p_event_id
      AND p.user_id = profiles.id
      AND COALESCE(p.score, 0) = 0
      AND p.completed_at IS NULL;

    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    SELECT user_id, v_wager, 'quiz_tournament_wager_refund', 'No-show refund (event: ' || p_event_id || ')', 'completed'
    FROM quiz_event_participants
    WHERE event_id = p_event_id AND COALESCE(score, 0) = 0 AND completed_at IS NULL;

    SELECT count(*) INTO v_players
    FROM quiz_event_participants
    WHERE event_id = p_event_id
      AND (COALESCE(score, 0) > 0 OR completed_at IS NOT NULL);

    v_pot := v_wager * v_players;

    IF v_players = 1 THEN
      -- Only one real player → refund.
      UPDATE profiles SET coins = coins + v_wager
      FROM quiz_event_participants p
      WHERE p.event_id = p_event_id AND p.user_id = profiles.id
        AND (COALESCE(p.score, 0) > 0 OR p.completed_at IS NOT NULL);
      INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
      SELECT user_id, v_wager, 'quiz_tournament_wager_refund', 'Solo refund (event: ' || p_event_id || ')', 'completed'
      FROM quiz_event_participants
      WHERE event_id = p_event_id AND (COALESCE(score, 0) > 0 OR completed_at IS NOT NULL);
    ELSIF v_players >= 2 THEN
      -- Ranked pays: 2 players → winner takes all; 3+ → 50/30/20.
      FOR v_ranked IN
        SELECT user_id, score
        FROM quiz_event_participants
        WHERE event_id = p_event_id
          AND (COALESCE(score, 0) > 0 OR completed_at IS NOT NULL)
        ORDER BY score DESC, correct_count DESC, completed_at ASC NULLS LAST
      LOOP
        v_rank := v_rank + 1;
        IF v_players = 2 THEN
          v_share := CASE WHEN v_rank = 1 THEN v_pot ELSE 0 END;
        ELSIF v_rank = 1 THEN
          v_share := v_pot * 50 / 100;
        ELSIF v_rank = 2 THEN
          v_share := v_pot * 30 / 100;
        ELSIF v_rank = 3 THEN
          v_share := v_pot * 20 / 100;
        ELSE
          v_share := 0;
        END IF;

        IF v_share > 0 THEN
          UPDATE profiles SET coins = coins + v_share WHERE id = v_ranked.user_id;
          INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
          VALUES (v_ranked.user_id, v_share, 'quiz_tournament_wager',
                  'Tournament prize #' || v_rank || ' (event: ' || p_event_id || ')', 'completed');
          v_payouts := v_payouts || jsonb_build_object(
            'rank', v_rank, 'user_id', v_ranked.user_id, 'amount', v_share
          );
        END IF;
      END LOOP;

      -- Integer rounding remainder (odd pots) → 1st place.
      IF v_players >= 2 THEN
        SELECT sum(amount) INTO v_remaining FROM jsonb_to_recordset(v_payouts) AS x(amount INT);
        IF COALESCE(v_remaining, 0) < v_pot THEN
          v_remaining := v_pot - COALESCE(v_remaining, 0);
          UPDATE profiles SET coins = coins + v_remaining
          WHERE id = (
            SELECT user_id FROM quiz_event_participants
            WHERE event_id = p_event_id AND (COALESCE(score, 0) > 0 OR completed_at IS NOT NULL)
            ORDER BY score DESC, correct_count DESC, completed_at ASC NULLS LAST
            LIMIT 1
          );
          INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
          SELECT user_id, v_remaining, 'quiz_tournament_wager',
                 'Tournament prize #1 remainder (event: ' || p_event_id || ')', 'completed'
          FROM quiz_event_participants
          WHERE event_id = p_event_id AND (COALESCE(score, 0) > 0 OR completed_at IS NOT NULL)
          ORDER BY score DESC, correct_count DESC, completed_at ASC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;
    END IF;
  END IF;

  UPDATE public.quiz_events SET status = 'completed', settled_at = now()
  WHERE id = p_event_id;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'wager_coins', v_wager,
    'players', v_players,
    'payouts', v_payouts
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.complete_quiz_event(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.complete_quiz_event(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_quiz_event(UUID) TO authenticated;

-- Host cancels: refunds every staked wager.
CREATE OR REPLACE FUNCTION public.cancel_quiz_event(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event RECORD;
  v_wager INT;
  v_refunded INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_event FROM public.quiz_events WHERE id = p_event_id FOR UPDATE;

  IF v_event IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  IF v_event.created_by <> v_uid
     AND NOT EXISTS (
       SELECT 1 FROM profiles
       WHERE id = v_uid AND role IN ('superadmin', 'employee', 'coa_employee')
     ) THEN
    RETURN jsonb_build_object('error', 'Only the host can cancel this event');
  END IF;

  IF v_event.settled_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Event already settled');
  END IF;

  IF v_event.status <> 'upcoming' THEN
    RETURN jsonb_build_object('error', 'Only upcoming events can be cancelled');
  END IF;

  v_wager := COALESCE(v_event.wager_coins, 0);

  IF v_wager > 0 THEN
    UPDATE profiles SET coins = coins + v_wager
    FROM quiz_event_participants p
    WHERE p.event_id = p_event_id AND p.user_id = profiles.id;

    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    SELECT user_id, v_wager, 'quiz_tournament_wager_refund', 'Event cancelled refund (event: ' || p_event_id || ')', 'completed'
    FROM quiz_event_participants
    WHERE event_id = p_event_id;

    GET DIAGNOSTICS v_refunded = ROW_COUNT;
  END IF;

  UPDATE public.quiz_events SET status = 'cancelled', settled_at = now()
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true, 'refunds', COALESCE(v_refunded, 0));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.cancel_quiz_event(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_quiz_event(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_quiz_event(UUID) TO authenticated;

-- =====================================================
-- 6. Realtime — live event leaderboards + invite updates.
-- =====================================================

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.quiz_event_participants;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.pvp_matches;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- quiz_event_participants peer reads need the helper visible; keep ACL tidy.
GRANT EXECUTE ON FUNCTION public._is_quiz_event_participant(UUID, UUID) TO authenticated;