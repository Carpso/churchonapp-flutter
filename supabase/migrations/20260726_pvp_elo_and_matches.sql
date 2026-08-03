-- =====================================================
-- PvP ELO Matchmaking Engine & Wager System
-- =====================================================

-- 1. Add ELO & Wager columns to pvp_matches (table already exists)
ALTER TABLE public.pvp_matches ADD COLUMN IF NOT EXISTS player1_elo_at_match INT NOT NULL DEFAULT 1200;
ALTER TABLE public.pvp_matches ADD COLUMN IF NOT EXISTS player2_elo_at_match INT;
ALTER TABLE public.pvp_matches ADD COLUMN IF NOT EXISTS wager_amount INT NOT NULL DEFAULT 0;
ALTER TABLE public.pvp_matches ADD COLUMN IF NOT EXISTS player1_elo_change INT;
ALTER TABLE public.pvp_matches ADD COLUMN IF NOT EXISTS player2_elo_change INT;

-- 2. Ensure pvp_answers table exists
CREATE TABLE IF NOT EXISTS public.pvp_answers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id UUID NOT NULL REFERENCES public.pvp_matches(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_index INT NOT NULL,
  selected_answer INT NOT NULL,
  response_time_ms INT NOT NULL DEFAULT 0,
  is_correct BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  tenant_id UUID REFERENCES public.tenants(id),
  church_id UUID REFERENCES public.churches(id)
);

-- 3. Add ELO columns to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS elo_rating INT NOT NULL DEFAULT 1200;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS highest_elo INT NOT NULL DEFAULT 1200;

-- 4. Add indexes for ELO matchmaking queries
CREATE INDEX IF NOT EXISTS idx_pvp_matches_pending_elo
  ON public.pvp_matches (status, player1_elo_at_match)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pvp_matches_status
  ON public.pvp_matches (status);

CREATE INDEX IF NOT EXISTS idx_profiles_elo
  ON public.profiles (elo_rating);

CREATE INDEX IF NOT EXISTS idx_pvp_answers_match
  ON public.pvp_answers (match_id);

-- 5. RLS policies for pvp_matches
ALTER TABLE public.pvp_matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pvp_matches_select_auth" ON public.pvp_matches;
CREATE POLICY "pvp_matches_select_auth"
  ON public.pvp_matches FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "pvp_matches_insert_auth" ON public.pvp_matches;
CREATE POLICY "pvp_matches_insert_auth"
  ON public.pvp_matches FOR INSERT TO authenticated
  WITH CHECK (player1_id = auth.uid());

DROP POLICY IF EXISTS "pvp_matches_update_players" ON public.pvp_matches;
CREATE POLICY "pvp_matches_update_players"
  ON public.pvp_matches FOR UPDATE TO authenticated
  USING (player1_id = auth.uid() OR player2_id = auth.uid())
  WITH CHECK (player1_id = auth.uid() OR player2_id = auth.uid());

-- 6. RLS policies for pvp_answers
ALTER TABLE public.pvp_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pvp_answers_select_auth" ON public.pvp_answers;
CREATE POLICY "pvp_answers_select_auth"
  ON public.pvp_answers FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "pvp_answers_insert_auth" ON public.pvp_answers;
CREATE POLICY "pvp_answers_insert_auth"
  ON public.pvp_answers FOR INSERT TO authenticated
  WITH CHECK (player_id = auth.uid());

-- 7. Atomic ELO calculation + wager settlement RPC
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
  v_wager_pot INT;
  v_winner_share INT;
  v_burn_share INT;
  v_loser_id UUID;
BEGIN
  -- Lock the match row
  SELECT * INTO v_match FROM pvp_matches WHERE id = p_match_id FOR UPDATE;

  IF v_match IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not found');
  END IF;

  IF v_match.status != 'completed' OR v_match.winner_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Match not completed or no winner');
  END IF;

  IF v_match.player2_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No player2 in match');
  END IF;

  -- Lock both player profiles
  SELECT * INTO v_player1 FROM profiles WHERE id = v_match.player1_id FOR UPDATE;
  SELECT * INTO v_player2 FROM profiles WHERE id = v_match.player2_id FOR UPDATE;

  -- Calculate expected scores (probability of winning)
  v_expected1 := 1.0 / (1.0 + power(10, (v_player2.elo_rating - v_player1.elo_rating)::NUMERIC / 400));
  v_expected2 := 1.0 - v_expected1;

  -- Determine actual scores
  IF v_match.winner_id = v_match.player1_id THEN
    v_actual1 := 1.0;
    v_actual2 := 0.0;
  ELSIF v_match.winner_id = v_match.player2_id THEN
    v_actual1 := 0.0;
    v_actual2 := 1.0;
  ELSE
    v_actual1 := 0.5;
    v_actual2 := 0.5;
  END IF;

  -- Calculate new ELO ratings
  v_elo_change1 := ROUND(v_k_factor * (v_actual1 - v_expected1))::INT;
  v_elo_change2 := ROUND(v_k_factor * (v_actual2 - v_expected2))::INT;

  v_new_elo1 := GREATEST(100, v_player1.elo_rating + v_elo_change1);
  v_new_elo2 := GREATEST(100, v_player2.elo_rating + v_elo_change2);

  -- Update player ELO ratings
  UPDATE profiles SET
    elo_rating = v_new_elo1,
    highest_elo = GREATEST(highest_elo, v_new_elo1)
  WHERE id = v_match.player1_id;

  UPDATE profiles SET
    elo_rating = v_new_elo2,
    highest_elo = GREATEST(highest_elo, v_new_elo2)
  WHERE id = v_match.player2_id;

  -- Record ELO changes on the match
  UPDATE pvp_matches SET
    player1_elo_change = v_elo_change1,
    player2_elo_change = v_elo_change2,
    player1_elo_at_match = v_player1.elo_rating,
    player2_elo_at_match = v_player2.elo_rating
  WHERE id = p_match_id;

  -- Handle wager settlement
  IF v_match.wager_amount > 0 THEN
    v_wager_pot := v_match.wager_amount * 2;
    v_winner_share := FLOOR(v_wager_pot * 0.9);
    v_burn_share := v_wager_pot - v_winner_share;

    -- Award winner (90% of pot)
    UPDATE profiles SET coins = coins + v_winner_share WHERE id = v_match.winner_id;

    -- Log winner coin addition
    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_match.winner_id, v_winner_share, 'pvp_wager', 'PvP wager win (match: ' || p_match_id || ')', 'completed');

    -- Burn 10% (no transfer — just log it)
    INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
    VALUES (v_match.winner_id, 0, 'pvp_wager_burn', 'Wager burn from match ' || p_match_id, 'completed');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'player1_elo_change', v_elo_change1,
    'player2_elo_change', v_elo_change2,
    'player1_new_elo', v_new_elo1,
    'player2_new_elo', v_new_elo2,
    'wager_settled', v_match.wager_amount > 0
  );
END;
$$;

-- 8. RPC: Deduct coins for wager (atomic, with balance check)
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
  -- Lock the profile row
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

-- 9. RPC: Refund wager coins (on timeout)
CREATE OR REPLACE FUNCTION public.refund_wager_coins(
  p_user_id UUID,
  p_amount INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles SET coins = coins + p_amount WHERE id = p_user_id;

  INSERT INTO coin_redemptions (user_id, amount, redemption_type, description, status)
  VALUES (p_user_id, p_amount, 'pvp_wager_refund', 'PvP wager refund (queue timeout)', 'completed');

  RETURN jsonb_build_object('success', true);
END;
$$;
