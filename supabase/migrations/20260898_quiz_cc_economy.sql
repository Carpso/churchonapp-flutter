-- 20260898_quiz_cc_economy.sql
-- Everything bible-quiz is CC: engine lease paid in CC, tournament prizes are
-- CC rewards (not kwacha), paid tournament passes can be bought with CC.
-- No real-money movement happens here; CC is bought separately with Lipila.

-- 1. Remote-config keys.
INSERT INTO public.platform_settings (key, value) VALUES
  ('quiz_lease_fee_cc', '1500'),
  ('quiz_prize_1st_cc', '500'),
  ('quiz_prize_2nd_cc', '300'),
  ('quiz_prize_3rd_cc', '150'),
  ('quiz_pass_cc_per_zmw', '1.0')
ON CONFLICT (key) DO NOTHING;

-- 2. Lease the Quiz Engine by spending CC (server-enforced amount, logged).
CREATE OR REPLACE FUNCTION public.lease_quiz_engine_cc()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_fee INT;
  v_coins INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT COALESCE((SELECT (value::numeric)::int
                     FROM public.platform_settings
                    WHERE key = 'quiz_lease_fee_cc'), 1500)
    INTO v_fee;

  SELECT coins INTO v_coins FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_coins IS NULL THEN
    RETURN jsonb_build_object('error', 'User not found');
  END IF;
  IF v_coins < v_fee THEN
    RETURN jsonb_build_object('error', 'Insufficient coins', 'balance', v_coins,
                              'required', v_fee);
  END IF;

  UPDATE public.profiles SET coins = coins - v_fee WHERE id = v_uid;

  INSERT INTO public.coin_redemptions (user_id, amount, redemption_type, description, status)
  VALUES (v_uid, v_fee, 'quiz_engine_lease',
          'Quiz Engine lease (' || v_fee || ' CC) — host church or personal tournaments', 'completed');

  RETURN jsonb_build_object('success', true, 'amount', v_fee);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.lease_quiz_engine_cc() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lease_quiz_engine_cc() FROM anon;
GRANT EXECUTE ON FUNCTION public.lease_quiz_engine_cc() TO authenticated;

-- 3. join_quiz_event — paid passes can now be paid in CC from the wallet.
--    p_pay_cc = true → deduct pass CC cost (pass_price × quiz_pass_cc_per_zmw)
--    and record a paid quiz_passes row instead of requiring Lipila first.
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

  -- Already a participant? Idempotent rejoin (no double charge).
  IF EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE user_id = v_uid AND event_id = p_event_id
  ) THEN
    RETURN jsonb_build_object('success', true, 'already_joined', true);
  END IF;

  -- Paid-pass events require a pass. Either a Lipila-paid quiz_passes row
  -- already exists, or the player pays in CC right now (p_pay_cc).
  IF COALESCE(v_event.pass_price, 0) > 0 THEN
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

      v_cc_cost := CEIL(COALESCE(v_event.pass_price, 0) * COALESCE(v_rate, 1.0));

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
      VALUES (p_event_id, v_uid, 'cc', v_cc_cost, v_event.pass_price, 'paid', now());

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
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_quiz_event(UUID, BOOLEAN) TO authenticated;