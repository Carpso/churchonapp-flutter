-- ============================================================================
-- 20261135_quiz_hosting_rpcs.sql
-- Makes the hosting engine actually usable.
--
-- Audit of 20261131 found it was 100% DB-only with several functional blockers:
--   1. `quiz_question_sets` / `quiz_set_questions` had SELECT-only policies, so
--      the "quiz master uploads a paper" flow was impossible from a client.
--   2. NO tournament lifecycle: status could never leave draft/scheduled;
--      `quiz_tournament_matches` was dead schema (no bracket, no results).
--   3. Invite status could never change (no accept/decline).
--   4. **LEASE DISCONNECT (blocker):** `lease_quiz_engine` demanded a confirmed
--      `coa_payments` (K1500) while the ONLY shipped lease UI charges 1500 CC
--      via `lease_quiz_engine_cc`, which never creates a `quiz_engine_leases`
--      row — so after paying CC, hosting still raised `lease_required`.
--   5. Study-pack hiding leaked: the owning tenant could read is_study_visible
--      = false questions, bypassing the study-pack gate for its own members.
--   6. Lease role list omitted `treasurer` (owner tier per 20261132).
--   7. REVOKE omitted `FROM PUBLIC`.
-- ============================================================================

-- ── 1. A lease is a lease: CC lease ALSO grants hosting ─────────────────────
CREATE OR REPLACE FUNCTION public.tenant_can_host_quiz(p_tenant_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.quiz_engine_leases l
      WHERE l.tenant_id = p_tenant_id
        AND l.status = 'active'
        AND l.ends_at > now()
    )
    OR EXISTS (
      -- Church Coins lease (the in-app path): a quiz_engine_lease redemption
      -- by any member of this tenant inside the last 365 days.
      SELECT 1
      FROM public.coin_redemptions cr
      JOIN public.profiles p ON p.id = cr.user_id
      WHERE cr.redemption_type = 'quiz_engine_lease'
        AND p.tenant_id = p_tenant_id
        AND cr.created_at > now() - interval '365 days'
    );
$$;

REVOKE EXECUTE ON FUNCTION public.tenant_can_host_quiz(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.tenant_can_host_quiz(text) FROM public;
GRANT EXECUTE ON FUNCTION public.tenant_can_host_quiz(text) TO authenticated;

-- `lease_quiz_engine` — accept treasurer, and ALSO accept a CC lease.
CREATE OR REPLACE FUNCTION public.lease_quiz_engine(
  p_season_label text DEFAULT NULL,
  p_payment_ref  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_tid      text;
  v_role     text;
  v_fee      numeric := 0;
  v_days     int := 365;
  v_paid     numeric := 0;
  v_cc       boolean := false;
  v_lease_id uuid;
  v_existing public.quiz_engine_leases%rowtype;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'no tenant';
  END IF;

  IF NOT public.is_owner_tier_role(v_role)
     AND lower(coalesce(v_role, '')) NOT IN
         ('superadmin', 'super_admin', 'coa_employee', 'employee',
          'admin', 'leader', 'department_leader') THEN
    RAISE EXCEPTION 'not authorised to lease the quiz engine';
  END IF;

  SELECT * INTO v_existing FROM public.quiz_engine_leases
   WHERE tenant_id = v_tid AND status = 'active' AND ends_at > now() LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('leased', true, 'already_active', true,
                              'lease_id', v_existing.id, 'ends_at', v_existing.ends_at);
  END IF;

  -- Already paid in Church Coins? Then it is leased — record it properly so
  -- hosting works from BOTH payment paths.
  SELECT EXISTS (
    SELECT 1 FROM public.coin_redemptions cr
    JOIN public.profiles p ON p.id = cr.user_id
    WHERE cr.redemption_type = 'quiz_engine_lease'
      AND p.tenant_id = v_tid
      AND cr.created_at > now() - interval '365 days'
  ) INTO v_cc;

  SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                    WHERE key = 'quiz_engine_lease_kwacha' LIMIT 1), 1500) INTO v_fee;
  SELECT COALESCE((SELECT value::int FROM public.platform_settings
                    WHERE key = 'quiz_engine_lease_days' LIMIT 1), 365) INTO v_days;

  SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM public.coa_payments
   WHERE user_id = v_uid
     AND status IN ('approved', 'completed', 'confirmed', 'settled')
     AND amount >= v_fee
     AND (p_payment_ref IS NULL OR payment_ref = p_payment_ref)
     AND created_at > now() - interval '90 days';

  IF NOT v_cc AND v_paid < v_fee THEN
    RETURN jsonb_build_object('leased', false, 'reason', 'payment_required',
                              'fee_kwacha', v_fee, 'paid', v_paid);
  END IF;

  INSERT INTO public.quiz_engine_leases
    (tenant_id, plan, season_label, starts_at, ends_at, fee_kwacha,
     payment_ref, status, auto_approved, approved_at, approved_by, created_by)
  VALUES
    (v_tid, 'season', p_season_label, now(),
     now() + make_interval(days => v_days),
     CASE WHEN v_cc THEN 0 ELSE v_fee END,
     p_payment_ref, 'active', true, now(), v_uid, v_uid)
  RETURNING id INTO v_lease_id;

  RETURN jsonb_build_object('leased', true, 'lease_id', v_lease_id,
                            'via', CASE WHEN v_cc THEN 'church_coins' ELSE 'coa_payments' END,
                            'ends_at', now() + make_interval(days => v_days));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.lease_quiz_engine(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.lease_quiz_engine(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.lease_quiz_engine(text, text) TO authenticated;

-- Hosting gate — lease OR CC lease.
CREATE OR REPLACE FUNCTION public.create_quiz_tournament(
  p_title            text,
  p_description      text DEFAULT NULL,
  p_question_set_id  uuid DEFAULT NULL,
  p_visibility       text DEFAULT 'tenant',
  p_format           text DEFAULT 'knockout',
  p_question_count   int  DEFAULT 10,
  p_time_per_question int DEFAULT 15,
  p_starts_at        timestamptz DEFAULT NULL,
  p_max_participants int  DEFAULT 32,
  p_invited_tenants  text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_tid    text;
  v_role   text;
  v_lease  uuid;
  v_id     uuid;
  v_t      text;
  v_set_ok boolean := true;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'no tenant';
  END IF;

  IF NOT public.is_owner_tier_role(v_role)
     AND lower(coalesce(v_role, '')) NOT IN
         ('superadmin', 'super_admin', 'coa_employee', 'employee',
          'admin', 'leader', 'department_leader') THEN
    RAISE EXCEPTION 'not authorised to host';
  END IF;

  -- HOSTING REQUIRES AN ACTIVE LEASE (Kwacha or Church Coins).
  IF NOT public.tenant_can_host_quiz(v_tid) THEN
    RAISE EXCEPTION 'lease_required';
  END IF;

  SELECT id INTO v_lease FROM public.quiz_engine_leases
   WHERE tenant_id = v_tid AND status = 'active' AND ends_at > now() LIMIT 1;

  IF p_visibility NOT IN ('tenant', 'invited', 'public') THEN
    RAISE EXCEPTION 'invalid visibility';
  END IF;

  -- The question set must belong to the host tenant.
  IF p_question_set_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.quiz_question_sets s
      WHERE s.id = p_question_set_id AND s.tenant_id = v_tid
    ) INTO v_set_ok;
    IF NOT v_set_ok THEN
      RAISE EXCEPTION 'question_set_not_yours';
    END IF;
  END IF;

  INSERT INTO public.quiz_tournaments
    (host_tenant_id, host_user_id, lease_id, question_set_id, title, description,
     format, visibility, max_participants, question_count, time_per_question,
     starts_at, status, created_by)
  VALUES
    (v_tid, v_uid, v_lease, p_question_set_id, p_title, p_description,
     COALESCE(p_format, 'knockout'), p_visibility,
     COALESCE(p_max_participants, 32), COALESCE(p_question_count, 10),
     COALESCE(p_time_per_question, 15), p_starts_at,
     CASE WHEN p_starts_at IS NULL THEN 'draft' ELSE 'scheduled' END, v_uid)
  RETURNING id INTO v_id;

  -- The HOST also competes against its invited tenants.
  INSERT INTO public.quiz_tournament_participants
    (tournament_id, user_id, tenant_id, team_name, is_host_side)
  VALUES (v_id, v_uid, v_tid, 'Host', true)
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  IF p_invited_tenants IS NOT NULL THEN
    FOREACH v_t IN ARRAY p_invited_tenants LOOP
      INSERT INTO public.quiz_tournament_invites
        (tournament_id, tenant_id, invited_by, status)
      VALUES (v_id, v_t, v_uid, 'invited')
      ON CONFLICT (tournament_id, tenant_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('tournament_id', v_id, 'visibility', p_visibility,
                            'status', CASE WHEN p_starts_at IS NULL
                                           THEN 'draft' ELSE 'scheduled' END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_quiz_tournament(text, text, uuid, text, text, int, int, timestamptz, int, text[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_quiz_tournament(text, text, uuid, text, text, int, int, timestamptz, int, text[]) FROM public;
GRANT EXECUTE ON FUNCTION public.create_quiz_tournament(text, text, uuid, text, text, int, int, timestamptz, int, text[]) TO authenticated;

-- ── 2. Question-set writers (was impossible from a client) ──────────────────
CREATE OR REPLACE FUNCTION public.create_quiz_set(
  p_title       text,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'no tenant'; END IF;

  INSERT INTO public.quiz_question_sets
    (tenant_id, lease_id, title, description, extract_status, created_by)
  VALUES
    (v_tid,
     (SELECT id FROM public.quiz_engine_leases
       WHERE tenant_id = v_tid AND status = 'active' AND ends_at > now() LIMIT 1),
     p_title, p_description, 'pending', v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('set_id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_quiz_set(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_quiz_set(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.create_quiz_set(text, text) TO authenticated;

-- Append parsed questions (used by the quiz-import extraction pipeline).
CREATE OR REPLACE FUNCTION public.add_quiz_set_questions(
  p_set_id    uuid,
  p_questions jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_own text;
  v_q   jsonb;
  v_n   int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;
  SELECT tenant_id INTO v_own FROM public.quiz_question_sets WHERE id = p_set_id;
  IF v_own IS NULL THEN RAISE EXCEPTION 'set_not_found'; END IF;
  IF v_own <> v_tid AND NOT EXISTS (
       SELECT 1 FROM public.profiles p WHERE p.id = v_uid
        AND p.role IN ('superadmin','super_admin','coa_employee','employee')) THEN
    RAISE EXCEPTION 'not_your_set';
  END IF;

  FOR v_q IN SELECT * FROM jsonb_array_elements(COALESCE(p_questions, '[]'::jsonb))
  LOOP
    IF COALESCE(v_q->>'prompt', '') = '' THEN CONTINUE; END IF;
    INSERT INTO public.quiz_set_questions
      (set_id, tenant_id, book, chapter, verse, verse_reference, category,
       difficulty, prompt, options, correct_answers, explanation, points,
       is_study_visible)
    VALUES (
      p_set_id, v_own,
      v_q->>'book',
      NULLIF(v_q->>'chapter', '')::int,
      NULLIF(v_q->>'verse', '')::int,
      v_q->>'verse_reference',
      v_q->>'category',
      v_q->>'difficulty',
      v_q->>'prompt',
      COALESCE(v_q->'options', '[]'::jsonb),
      COALESCE(v_q->'correct_answers', '[]'::jsonb),
      v_q->>'explanation',
      COALESCE(NULLIF(v_q->>'points', '')::int, 10),
      COALESCE((v_q->>'is_study_visible')::boolean, true)
    );
    v_n := v_n + 1;
  END LOOP;

  UPDATE public.quiz_question_sets
     SET extract_status = 'ready', extracted_count = extracted_count + v_n
   WHERE id = p_set_id;

  RETURN jsonb_build_object('inserted', v_n);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_quiz_set_questions(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.add_quiz_set_questions(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.add_quiz_set_questions(uuid, jsonb) TO authenticated;

-- ── 3. Tournament lifecycle ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_quiz_set_extract_status(
  p_set_id uuid,
  p_status text,
  p_error  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.quiz_question_sets
     SET extract_status = p_status, extract_error = p_error
   WHERE id = p_set_id
     AND tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_quiz_set_extract_status(uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_quiz_set_extract_status(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.set_quiz_set_extract_status(uuid, text, text) TO authenticated;

-- Start a tournament (draft/scheduled -> live).
CREATE OR REPLACE FUNCTION public.start_quiz_tournament(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_t   public.quiz_tournaments%rowtype;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_t FROM public.quiz_tournaments WHERE id = p_tournament_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('started', false, 'reason', 'not_found'); END IF;
  IF v_t.host_tenant_id <> v_tid THEN
    RETURN jsonb_build_object('started', false, 'reason', 'not_host');
  END IF;
  IF v_t.status NOT IN ('draft', 'scheduled') THEN
    RETURN jsonb_build_object('started', false, 'reason', 'already_' || v_t.status);
  END IF;

  UPDATE public.quiz_tournaments SET status = 'live' WHERE id = p_tournament_id;
  RETURN jsonb_build_object('started', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.start_quiz_tournament(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.start_quiz_tournament(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.start_quiz_tournament(uuid) TO authenticated;

-- Generate the knockout bracket (handles byes for odd counts).
CREATE OR REPLACE FUNCTION public.generate_quiz_bracket(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_t   public.quiz_tournaments%rowtype;
  v_ids uuid[];
  v_n   int;
  v_i   int := 1;
  v_slot int := 1;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_t FROM public.quiz_tournaments WHERE id = p_tournament_id;
  IF NOT FOUND OR v_t.host_tenant_id <> v_tid THEN
    RETURN jsonb_build_object('generated', false, 'reason', 'not_host');
  END IF;

  -- Seeded order: highest score first.
  SELECT array_agg(user_id ORDER BY score DESC, created_at ASC)
    INTO v_ids
    FROM public.quiz_tournament_participants
   WHERE tournament_id = p_tournament_id AND status <> 'withdrawn';

  v_n := COALESCE(array_length(v_ids, 1), 0);
  IF v_n < 2 THEN
    RETURN jsonb_build_object('generated', false, 'reason', 'need_two_players');
  END IF;

  DELETE FROM public.quiz_tournament_matches WHERE tournament_id = p_tournament_id;

  WHILE v_i < v_n LOOP
    INSERT INTO public.quiz_tournament_matches
      (tournament_id, round, slot, home_user_id, away_user_id, status)
    VALUES (p_tournament_id, 1, v_slot, v_ids[v_i],
            CASE WHEN v_i + 1 <= v_n THEN v_ids[v_i + 1] END,
            CASE WHEN v_i + 1 <= v_n THEN 'pending' ELSE 'bye' END);
    IF v_i + 1 > v_n THEN
      UPDATE public.quiz_tournament_matches
         SET winner_user_id = v_ids[v_i]
       WHERE tournament_id = p_tournament_id AND round = 1 AND slot = v_slot;
    END IF;
    v_i := v_i + 2;
    v_slot := v_slot + 1;
  END LOOP;

  RETURN jsonb_build_object('generated', true, 'round1_matches', v_slot - 1);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_quiz_bracket(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.generate_quiz_bracket(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.generate_quiz_bracket(uuid) TO authenticated;

-- Record a bracket result and advance the winner into the next round.
CREATE OR REPLACE FUNCTION public.record_quiz_match_result(
  p_match_id uuid,
  p_home_score int,
  p_away_score int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_tid    text;
  v_m      public.quiz_tournament_matches%rowtype;
  v_t      public.quiz_tournaments%rowtype;
  v_winner uuid;
  v_next_slot int;
  v_next_round int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_m FROM public.quiz_tournament_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('recorded', false, 'reason', 'not_found'); END IF;

  SELECT * INTO v_t FROM public.quiz_tournaments WHERE id = v_m.tournament_id;
  IF v_t.host_tenant_id <> v_tid THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'not_host');
  END IF;

  v_winner := CASE WHEN COALESCE(p_home_score,0) >= COALESCE(p_away_score,0)
                   THEN v_m.home_user_id ELSE v_m.away_user_id END;

  UPDATE public.quiz_tournament_matches
     SET home_score = p_home_score, away_score = p_away_score,
         winner_user_id = v_winner, status = 'completed', completed_at = now()
   WHERE id = p_match_id;

  -- Move the winner forward if a next round is needed.
  SELECT count(*) INTO v_next_round FROM public.quiz_tournament_matches
   WHERE tournament_id = v_m.tournament_id;

  IF v_next_round > 1 THEN
    v_next_slot := (v_m.slot + 1) / 2;
    INSERT INTO public.quiz_tournament_matches
      (tournament_id, round, slot, home_user_id, status)
    VALUES (v_m.tournament_id, v_m.round + 1, v_next_slot, v_winner, 'pending')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN jsonb_build_object('recorded', true, 'winner_user_id', v_winner);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_quiz_match_result(uuid, int, int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_quiz_match_result(uuid, int, int) FROM public;
GRANT EXECUTE ON FUNCTION public.record_quiz_match_result(uuid, int, int) TO authenticated;

-- ── 4. Invite accept / decline ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.respond_quiz_tournament_invite(
  p_tournament_id uuid,
  p_accept boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  UPDATE public.quiz_tournament_invites
     SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END
   WHERE tournament_id = p_tournament_id AND tenant_id = v_tid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_invite');
  END IF;

  RETURN jsonb_build_object('ok', true, 'accepted', p_accept);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.respond_quiz_tournament_invite(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.respond_quiz_tournament_invite(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.respond_quiz_tournament_invite(uuid, boolean) TO authenticated;

-- ── 5. Study-pack leak fix ──────────────────────────────────────────────────
-- Only owner-tier / staff may read hidden questions; ordinary members of the
-- host tenant must go through the study-pack gate like everyone else.
DROP POLICY IF EXISTS "quiz_set_questions_owner_read" ON public.quiz_set_questions;
CREATE POLICY "quiz_set_questions_owner_read"
  ON public.quiz_set_questions FOR SELECT TO authenticated
  USING (
    (
      tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
      AND (
        is_study_visible
        OR public.is_tenant_owner(
             (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid()))
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- Invited tenants can see the set METADATA of tournaments they are in.
DROP POLICY IF EXISTS "quiz_sets_invited_read" ON public.quiz_question_sets;
CREATE POLICY "quiz_sets_invited_read"
  ON public.quiz_question_sets FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.quiz_tournaments t
      WHERE t.question_set_id = quiz_question_sets.id
        AND (
          t.visibility = 'public'
          OR EXISTS (
            SELECT 1 FROM public.quiz_tournament_invites i
            WHERE i.tournament_id = t.id
              AND i.tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
          )
          OR EXISTS (
            SELECT 1 FROM public.quiz_tournament_participants tp
            WHERE tp.tournament_id = t.id AND tp.user_id = auth.uid()
          )
        )
    )
  );

-- ── 6. Bracket integrity ────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS ux_quiz_tmatch_slot
  ON public.quiz_tournament_matches (tournament_id, round, slot);
