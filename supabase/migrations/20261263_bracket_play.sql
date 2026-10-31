-- ============================================================================
-- 20261263 — TOURNAMENT BRACKET PLAY
--
-- Makes bracket matches PLAYABLE in-app (they previously existed only as rows
-- the host hand-entered scores into) and fixes three latent bracket bugs:
--
--   BUG 1 (lost winner): record_quiz_match_result advanced by INSERTing the
--   winner into the next-round slot with ON CONFLICT DO NOTHING — the SECOND
--   winner of a pair hit the unique (tournament_id, round, slot) conflict and
--   was silently DROPPED, so the next match could never have two players.
--
--   BUG 2 (phantom round): the advance condition was count(all matches) > 1,
--   so completing the FINAL match spawned an endless series of empty rounds.
--
--   BUG 3 (stuck byes): bye winners never advanced — only "real" matches
--   triggered anything, so odd-sized brackets dead-ended.
--
-- NEW MODEL: a match completes → when every playable match in its round is
-- finished, the round's winners (INCLUDING byes) are seeded into the next
-- round with the same pairing logic as generate_quiz_bracket; the last
-- winner completes the tournament. Results flow from BOTH paths:
--   * the host hand-recording (record_quiz_match_result, unchanged signature),
--   * the arena finishing a real PvP match (trigger on pvp_matches).
--
-- Tables are empty in production (feature never used live), so the old
-- advance logic is replaced outright with no data migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Seed the next round from a completed round's winners (incl. byes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.seed_next_bracket_round(
  p_tournament_id uuid,
  p_round integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ids  uuid[];
  v_n    integer;
  v_i    integer := 1;
  v_slot integer := 1;
  v_existing integer;
BEGIN
  SELECT array_agg(winner_user_id ORDER BY slot)
    INTO v_ids
    FROM public.quiz_tournament_matches
   WHERE tournament_id = p_tournament_id
     AND round = p_round
     AND winner_user_id IS NOT NULL;

  v_n := COALESCE(array_length(v_ids, 1), 0);
  IF v_n = 0 THEN
    RETURN jsonb_build_object('seeded', false, 'reason', 'no_winners');
  END IF;

  -- One winner left: the tournament is decided.
  IF v_n = 1 THEN
    UPDATE public.quiz_tournaments
       SET status = 'completed',
           ends_at = COALESCE(ends_at, now()),
           updated_at = now()
     WHERE id = p_tournament_id;
    RETURN jsonb_build_object('seeded', false, 'tournament_completed', true);
  END IF;

  -- Safety: never double-seed a round.
  SELECT count(*) INTO v_existing
    FROM public.quiz_tournament_matches
   WHERE tournament_id = p_tournament_id AND round = p_round + 1;
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('seeded', false, 'reason', 'already_seeded');
  END IF;

  -- Same pairing shape as generate_quiz_bracket: seeded pairs, last odd slot
  -- becomes a bye whose winner is already decided.
  WHILE v_i <= v_n LOOP
    INSERT INTO public.quiz_tournament_matches
      (tournament_id, round, slot, home_user_id, away_user_id, status)
    VALUES (p_tournament_id, p_round + 1, v_slot, v_ids[v_i],
            CASE WHEN v_i + 1 <= v_n THEN v_ids[v_i + 1] END,
            CASE WHEN v_i + 1 <= v_n THEN 'pending' ELSE 'bye' END);
    IF v_i + 1 > v_n THEN
      UPDATE public.quiz_tournament_matches
         SET winner_user_id = v_ids[v_i]
       WHERE tournament_id = p_tournament_id
         AND round = p_round + 1 AND slot = v_slot;
    END IF;
    v_i := v_i + 2;
    v_slot := v_slot + 1;
  END LOOP;

  RETURN jsonb_build_object('seeded', true, 'matches', v_slot - 1);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Apply a result to a bracket match, then seed forward when the round ends
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.apply_bracket_result(
  p_bracket_match_id uuid,
  p_home_score integer,
  p_away_score integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m         public.quiz_tournament_matches%ROWTYPE;
  v_open      integer;
  v_seed      jsonb := NULL;
BEGIN
  SELECT * INTO v_m
    FROM public.quiz_tournament_matches
   WHERE id = p_bracket_match_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'not_found');
  END IF;
  IF v_m.status = 'completed' THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'already_completed');
  END IF;

  UPDATE public.quiz_tournament_matches
     SET home_score = COALESCE(p_home_score, 0),
         away_score = COALESCE(p_away_score, 0),
         winner_user_id = CASE
           WHEN COALESCE(p_home_score, 0) >= COALESCE(p_away_score, 0)
             THEN v_m.home_user_id
           ELSE v_m.away_user_id
         END,
         status = 'completed',
         completed_at = now()
   WHERE id = p_bracket_match_id;

  -- Round finished? (bye rows never block — they are not pending/playing)
  SELECT count(*) INTO v_open
    FROM public.quiz_tournament_matches
   WHERE tournament_id = v_m.tournament_id
     AND round = v_m.round
     AND status IN ('pending', 'playing')
     AND id <> p_bracket_match_id;

  IF v_open = 0 THEN
    v_seed := private.seed_next_bracket_round(v_m.tournament_id, v_m.round);
  END IF;

  RETURN jsonb_build_object('applied', true, 'seed', to_jsonb(v_seed));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. record_quiz_match_result: same host-gated signature, fixed internals
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_quiz_match_result(
  p_match_id uuid,
  p_home_score integer,
  p_away_score integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_host text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  SELECT t.host_tenant_id INTO v_host
    FROM public.quiz_tournament_matches m
    JOIN public.quiz_tournaments t ON t.id = m.tournament_id
   WHERE m.id = p_match_id;
  IF v_host IS NULL THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'not_found');
  END IF;
  IF v_host <> v_tid THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'not_host');
  END IF;

  RETURN jsonb_build_object('recorded', true)
    || private.apply_bracket_result(p_match_id, p_home_score, p_away_score);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_quiz_match_result(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_quiz_match_result(uuid, integer, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. PLAY: a participant (or the host) turns a bracket slot into a real
--    zero-wager PvP match and notifies the opponent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_bracket_match(p_bracket_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_elo  integer;
  v_m    public.quiz_tournament_matches%ROWTYPE;
  v_t    public.quiz_tournaments%ROWTYPE;
  v_pvp  uuid;
  v_opp  uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  SELECT tenant_id, elo_rating INTO v_tid, v_elo FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_m
    FROM public.quiz_tournament_matches
   WHERE id = p_bracket_match_id
   FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Match not found'); END IF;
  IF v_m.home_user_id IS NULL OR v_m.away_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'This slot is not a playable match yet');
  END IF;
  IF v_m.match_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'This match has already started');
  END IF;
  IF COALESCE(v_m.status, 'pending') <> 'pending' THEN
    RETURN jsonb_build_object('error', 'This match is not playable right now');
  END IF;

  SELECT * INTO v_t FROM public.quiz_tournaments WHERE id = v_m.tournament_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Tournament not found'); END IF;
  IF v_t.status IN ('cancelled', 'completed') THEN
    RETURN jsonb_build_object('error', 'This tournament is closed');
  END IF;

  IF v_uid NOT IN (v_m.home_user_id, v_m.away_user_id)
     AND v_t.host_tenant_id <> v_tid THEN
    RETURN jsonb_build_object('error', 'Only the two players or the host can start this match');
  END IF;

  v_opp := CASE WHEN v_uid = v_m.home_user_id THEN v_m.away_user_id ELSE v_m.home_user_id END;

  -- Zero-wager PvP match (tournament entry is paid separately); bracket home
  -- is ALWAYS pvp player1 so the result trigger's score mapping is stable.
  v_pvp := gen_random_uuid();
  INSERT INTO public.pvp_matches (
    id, player1_id, player2_id, status, channel_name,
    question_count, time_per_question, wager_amount,
    player1_elo_at_match, tenant_id, is_invite
  ) VALUES (
    v_pvp, v_m.home_user_id, v_m.away_user_id, 'invited',
    'pvp_' || v_pvp::text,
    GREATEST(LEAST(COALESCE(v_t.question_count, 10), 30), 5),
    GREATEST(LEAST(COALESCE(v_t.time_per_question, 15), 30), 5),
    0, v_elo, v_tid, true
  );

  UPDATE public.quiz_tournament_matches
     SET match_id = v_pvp, status = 'playing', started_at = now()
   WHERE id = p_bracket_match_id;

  -- In-app notification; the reference routes to /quiz/invite/<matchId>
  -- (the existing PvP invite handler), so the opponent lands in the arena.
  INSERT INTO public.notifications (user_id, title, body, is_read, type, reference_id)
  VALUES (v_opp, 'Tournament Match Ready',
          'Your tournament match is ready. Tap to play!', false, 'quiz', v_pvp::text);

  RETURN jsonb_build_object('success', true, 'match_id', v_pvp);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.start_bracket_match(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_bracket_match(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Auto-record: a completed PvP match that belongs to a bracket slot writes
--    the bracket result. Fires on score updates too, because
--    complete_pvp_match sets status FIRST and the scores land afterwards in
--    calculate_elo_and_award_wager's own UPDATE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.sync_bracket_from_pvp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bm   record;
  v_home integer;
  v_away integer;
BEGIN
  IF NEW.status <> 'completed' THEN RETURN NEW; END IF;
  -- The status-only UPDATE fires before scores exist; wait for the score write.
  IF NEW.player1_score IS NULL AND NEW.player2_score IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_bm
    FROM public.quiz_tournament_matches
   WHERE match_id = NEW.id
     AND status <> 'completed'
   LIMIT 1;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_home := CASE
    WHEN v_bm.home_user_id = NEW.player1_id THEN COALESCE(NEW.player1_score, 0)
    WHEN v_bm.home_user_id = NEW.player2_id THEN COALESCE(NEW.player2_score, 0)
  END;
  v_away := CASE
    WHEN v_bm.away_user_id = NEW.player1_id THEN COALESCE(NEW.player1_score, 0)
    WHEN v_bm.away_user_id = NEW.player2_id THEN COALESCE(NEW.player2_score, 0)
  END;
  IF v_home IS NULL OR v_away IS NULL THEN RETURN NEW; END IF;

  PERFORM private.apply_bracket_result(v_bm.id, v_home, v_away);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pvp_matches_bracket_sync ON public.pvp_matches;
CREATE TRIGGER trg_pvp_matches_bracket_sync
AFTER UPDATE OF status, player1_score, player2_score ON public.pvp_matches
FOR EACH ROW EXECUTE FUNCTION private.sync_bracket_from_pvp();

-- ---------------------------------------------------------------------------
-- 6. Verification
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_fail text := '';
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'start_bracket_match') <> 1 THEN
    v_fail := v_fail || ' start_rpc;';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'apply_bracket_result') <> 1 THEN
    v_fail := v_fail || ' apply_fn;';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'seed_next_bracket_round') <> 1 THEN
    v_fail := v_fail || ' seed_fn;';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.pvp_matches'::regclass
                    AND tgname = 'trg_pvp_matches_bracket_sync'
                    AND NOT tgisinternal) THEN
    v_fail := v_fail || ' trigger;';
  END IF;
  IF v_fail <> '' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED:%', v_fail;
  END IF;
  RAISE NOTICE 'bracket play: all checks passed';
END;
$$;
