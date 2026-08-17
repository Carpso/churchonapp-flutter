-- 20260904: Quiz batch fixes
-- 1. Global CC leaderboard: ALL tenants, ranked by Church Coin balance
--    (profiles.coins). "Public" = registered church member (tenant_id set)
--    and not opted out via hide_from_leaderboard.
-- 2. can_manage_quiz_content(): superadmin/coa_employee/employee OR any user
--    whose church has leased the Quiz Engine (coin_redemptions
--    redemption_type = 'quiz_engine_lease').
-- 3. quiz_generation_log: audit/rate-limit table for AI question generation
--    and imports (written by Edge Functions via service role).
-- 4. join_quiz_event: reads `pass_price` which does NOT exist on quiz_events
--    (columns are pass_price_zmw/pass_price_cc) -> every premium-join RPC
--    call raised 42703 "column pass_price does not exist". Recreated with
--    pass_price_zmw.
-- 5. pvp_matches.tenant_id: uuid -> text (profiles.tenant_id is TEXT;
--    seed tenants zm_1/zw_* made client inserts/joins fail with
--    invalid-input-syntax-for-uuid -> PvP matchmaking dead for seed users).

-- ── 1. profiles: leaderboard opt-out ─────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS hide_from_leaderboard BOOLEAN NOT NULL DEFAULT false;

-- ── 2. Global Church Coin leaderboard (all tenants) ───────────────────────
CREATE OR REPLACE FUNCTION public.get_quiz_cc_leaderboard(
  p_limit INT DEFAULT 50,
  p_min_coins INT DEFAULT 0
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  avatar_url TEXT,
  church_name TEXT,
  coins BIGINT,
  correct_answers BIGINT,
  games_played BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
BEGIN
  RETURN QUERY
  WITH activity AS (
    SELECT pa.player_id AS uid,
           COUNT(*) FILTER (WHERE qq.correct_answer IS NOT NULL
                             AND pa.selected_answer = qq.correct_answer) AS correct,
           COUNT(DISTINCT pa.match_id) AS games
    FROM public.pvp_answers pa
    LEFT JOIN public.quiz_questions qq ON qq.id = pa.question_id
    GROUP BY pa.player_id
    UNION ALL
    SELECT dc.user_id AS uid,
           COALESCE(SUM(dc.correct_count), 0)::BIGINT AS correct,
           COUNT(*) AS games
    FROM public.daily_challenge_results dc
    GROUP BY dc.user_id
  ),
  totals AS (
    SELECT uid,
           SUM(correct)::BIGINT AS correct,
           SUM(games)::BIGINT AS games
    FROM activity
    GROUP BY uid
  )
  SELECT
    p.id AS user_id,
    COALESCE(p.full_name, 'Quiz Player')::TEXT AS full_name,
    COALESCE(p.avatar_url, '')::TEXT AS avatar_url,
    COALESCE(t.name, '')::TEXT AS church_name,
    COALESCE(p.coins, 0)::BIGINT AS coins,
    COALESCE(a.correct, 0)::BIGINT AS correct_answers,
    COALESCE(a.games, 0)::BIGINT AS games_played
  FROM public.profiles p
  LEFT JOIN public.tenants t ON t.id::text = p.tenant_id::text
  LEFT JOIN totals a ON a.uid = p.id
  WHERE p.tenant_id IS NOT NULL
    AND COALESCE(p.coins, 0) >= COALESCE(p_min_coins, 0)
    AND NOT COALESCE(p.hide_from_leaderboard, false)
  ORDER BY p.coins DESC, a.correct DESC NULLS LAST, p.full_name ASC
  LIMIT v_limit;
END;
$$;
ALTER FUNCTION public.get_quiz_cc_leaderboard(INT, INT) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) TO authenticated;

-- ── 3. Content-management gate (admins + quiz-engine leasing tenants) ─────
CREATE OR REPLACE FUNCTION public.can_manage_quiz_content()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_tid TEXT;
  v_leased BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'Not authenticated');
  END IF;

  SELECT role, tenant_id INTO v_role, v_tid
  FROM public.profiles WHERE id = v_uid;

  IF v_role IN ('superadmin', 'coa_employee', 'employee') THEN
    RETURN jsonb_build_object('allowed', true, 'role', v_role, 'leased', false);
  END IF;

  IF v_tid IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.coin_redemptions cr
      JOIN public.profiles p ON p.id = cr.user_id
      WHERE cr.redemption_type = 'quiz_engine_lease'
        AND p.tenant_id::text = v_tid
    ) INTO v_leased;
    IF COALESCE(v_leased, false) THEN
      RETURN jsonb_build_object('allowed', true, 'role', v_role, 'leased', true);
    END IF;
  END IF;

  RETURN jsonb_build_object('allowed', false, 'role', v_role, 'reason', 'Quiz Engine lease required');
END;
$$;
ALTER FUNCTION public.can_manage_quiz_content() OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.can_manage_quiz_content() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_manage_quiz_content() FROM anon;
GRANT EXECUTE ON FUNCTION public.can_manage_quiz_content() TO authenticated;

-- ── 4. AI generation audit / rate-limit log ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.quiz_generation_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  batch_id TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'auto',
  inserted INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.quiz_generation_log ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_quiz_gen_log_user_time
  ON public.quiz_generation_log (user_id, created_at DESC);

-- ── 5. join_quiz_event: use the real pass_price_zmw column ────────────────
DROP FUNCTION IF EXISTS public.join_quiz_event(UUID);
DROP FUNCTION IF EXISTS public.join_quiz_event(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION public.join_quiz_event(p_event_id UUID, p_pay_cc BOOLEAN DEFAULT false)
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
  v_cc_cost INT;
  v_rate NUMERIC;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT status, pass_price_zmw, max_participants, wager_coins
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

  -- Already a participant? Idempotent rejoin (no double charge).
  IF EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE user_id = v_uid AND event_id = p_event_id
  ) THEN
    RETURN jsonb_build_object('success', true, 'already_joined', true);
  END IF;

  -- Paid-pass events require a pass. Either a Lipila-paid quiz_passes row
  -- already exists, or the player pays in CC right now (p_pay_cc).
  IF COALESCE(v_event.pass_price_zmw, 0) > 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM public.quiz_passes
      WHERE event_id = p_event_id AND user_id = v_uid AND status = 'paid'
    ) INTO v_paid;
    IF NOT COALESCE(v_paid, false) THEN
      IF NOT COALESCE(p_pay_cc, false) THEN
        RETURN jsonb_build_object('error', 'Paid pass required');
      END IF;

      SELECT COALESCE((SELECT value::numeric
                         FROM public.platform_settings
                        WHERE key = 'quiz_pass_cc_per_zmw'), 1.0)
        INTO v_rate;

      v_cc_cost := CEIL(COALESCE(v_event.pass_price_zmw, 0) * COALESCE(v_rate, 1.0));

      SELECT coins INTO v_coins FROM public.profiles WHERE id = v_uid FOR UPDATE;
      IF v_coins IS NULL THEN
        RETURN jsonb_build_object('error', 'User not found');
      END IF;
      IF v_coins < v_cc_cost THEN
        RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_coins,
                                  'required', v_cc_cost);
      END IF;

      UPDATE public.profiles SET coins = coins - v_cc_cost WHERE id = v_uid;

      INSERT INTO public.quiz_passes (event_id, user_id, payment_method, amount_cc,
                                      amount_zmw, status, purchased_at)
      VALUES (p_event_id, v_uid, 'cc', v_cc_cost, v_event.pass_price_zmw, 'paid', now());

      INSERT INTO public.coin_redemptions (user_id, amount, redemption_type, description, status)
      VALUES (v_uid, v_cc_cost, 'quiz_tournament_pass',
              'Paid tournament pass in CC (event: ' || p_event_id || ')', 'completed');
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
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) TO authenticated;

-- ── 6. pvp_matches.tenant_id: uuid -> text (matches profiles.tenant_id) ───
-- FK to tenants(id) is dropped: profiles.tenant_id is TEXT with the same
-- mismatch (documented known issue) and RLS never joins on the FK.
ALTER TABLE public.pvp_matches DROP CONSTRAINT IF EXISTS pvp_matches_tenant_id_fkey;
ALTER TABLE public.pvp_matches DROP CONSTRAINT IF EXISTS pvp_matches_church_id_fkey;

ALTER TABLE public.pvp_matches
  ALTER COLUMN tenant_id TYPE TEXT USING tenant_id::text;