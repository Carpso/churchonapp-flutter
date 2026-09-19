-- ============================================================================
-- 20261205_quiz_tournament_admin_rewards.sql
-- Platform (superadmin / COA) tournament control + a configurable rewarding
-- system for tournaments.
--
-- What this adds on top of 20261131 + 20261135:
--   * Full scheduling on quiz_tournaments: season label, custom duration in
--     weeks OR months, recurrence (+ a spawn RPC), registration windows.
--   * Entry fee (CC or free) + prize configuration (1st/2nd/3rd + participation
--     + streak) stored per tournament, with platform_settings as the default.
--   * Platform/staff tournaments do NOT require a church lease.
--   * `quiz_tournament_awards` (one award per user per type per tournament) +
--     auto-award on completion (server-side, idempotent) + manual award/revoke.
--   * `is_featured` so staff can promote a tournament onto the hub for everyone.
-- ============================================================================

-- ── 1. Extend quiz_tournaments ──────────────────────────────────────────────
ALTER TABLE public.quiz_tournaments
  ADD COLUMN IF NOT EXISTS season_label           text,
  ADD COLUMN IF NOT EXISTS duration_weeks         int,
  ADD COLUMN IF NOT EXISTS duration_months        int,
  ADD COLUMN IF NOT EXISTS recurrence             text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS recurrence_interval    int NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS recurrence_until       timestamptz,
  ADD COLUMN IF NOT EXISTS registration_opens_at  timestamptz,
  ADD COLUMN IF NOT EXISTS registration_closes_at timestamptz,
  ADD COLUMN IF NOT EXISTS entry_fee_cc           int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS entry_fee_kwacha       numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS prize_1st_cc           int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS prize_2nd_cc           int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS prize_3rd_cc           int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS participation_reward_cc int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS streak_reward_cc       int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS prize_config           jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS is_featured            boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS banner_url             text,
  ADD COLUMN IF NOT EXISTS entry_promo_code       text,
  ADD COLUMN IF NOT EXISTS is_promo               boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS platform_hosted        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS published_at           timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at             timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS cancelled_reason       text;

CREATE INDEX IF NOT EXISTS idx_quiz_tournaments_featured
  ON public.quiz_tournaments (is_featured, status) WHERE is_featured;

-- Keep updated_at fresh.
CREATE OR REPLACE FUNCTION public.touch_quiz_tournaments_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_quiz_tournaments_updated_at ON public.quiz_tournaments;
CREATE TRIGGER trg_quiz_tournaments_updated_at
  BEFORE UPDATE ON public.quiz_tournaments
  FOR EACH ROW EXECUTE FUNCTION public.touch_quiz_tournaments_updated_at();

-- ── 2. Awards ledger ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.quiz_tournament_awards (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.quiz_tournaments(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rank           int,
  award_type     text NOT NULL DEFAULT 'prize', -- prize | participation | streak | manual
  cc_amount      int NOT NULL DEFAULT 0,
  promo_code     text,
  label          text,
  status         text NOT NULL DEFAULT 'awarded', -- awarded | revoked
  awarded_by     uuid,
  awarded_at     timestamptz NOT NULL DEFAULT now(),
  revoked_by     uuid,
  revoked_at     timestamptz,
  UNIQUE (tournament_id, user_id, award_type)
);

CREATE INDEX IF NOT EXISTS idx_quiz_awards_tournament
  ON public.quiz_tournament_awards (tournament_id, rank);
CREATE INDEX IF NOT EXISTS idx_quiz_awards_user
  ON public.quiz_tournament_awards (user_id, awarded_at DESC);

ALTER TABLE public.quiz_tournament_awards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_awards_own_read" ON public.quiz_tournament_awards;
CREATE POLICY "quiz_awards_own_read"
  ON public.quiz_tournament_awards FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_platform_staff()
  );

-- ── 3. Staff helper ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_platform_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_platform_staff() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_platform_staff() FROM public;
GRANT EXECUTE ON FUNCTION public.is_platform_staff() TO authenticated;

-- Default prize amounts live in platform_settings; the per-tournament columns
-- override them. Nothing is hardcoded in the client.
INSERT INTO public.platform_settings (key, value)
VALUES
  ('quiz_prize_1st_cc', '500'),
  ('quiz_prize_2nd_cc', '300'),
  ('quiz_prize_3rd_cc', '150'),
  ('quiz_tournament_entry_fee_cc', '0'),
  ('quiz_tournament_participation_reward_cc', '0')
ON CONFLICT (key) DO NOTHING;

-- ── 4. Create (staff) ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_quiz_tournament_admin(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_tid    text;
  v_host   uuid;
  v_id     uuid;
  v_start  timestamptz;
  v_end    timestamptz;
  v_weeks  int;
  v_months int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  v_host  := NULLIF(p_payload->>'host_user_id', '')::uuid;
  v_start := NULLIF(p_payload->>'starts_at', '')::timestamptz;
  v_end   := NULLIF(p_payload->>'ends_at', '')::timestamptz;
  v_weeks := NULLIF(p_payload->>'duration_weeks', '')::int;
  v_months := NULLIF(p_payload->>'duration_months', '')::int;

  -- Derive ends_at from a duration when an explicit end was not supplied.
  IF v_end IS NULL AND v_start IS NOT NULL THEN
    IF v_weeks IS NOT NULL AND v_weeks > 0 THEN
      v_end := v_start + make_interval(weeks => v_weeks);
    ELSIF v_months IS NOT NULL AND v_months > 0 THEN
      v_end := v_start + make_interval(months => v_months);
    END IF;
  END IF;

  INSERT INTO public.quiz_tournaments (
    host_tenant_id, host_user_id, lease_id, question_set_id, title, description,
    format, visibility, allow_host_plays, max_participants, question_count,
    time_per_question, starts_at, ends_at, status, season_label, duration_weeks,
    duration_months, recurrence, recurrence_interval, recurrence_until,
    registration_opens_at, registration_closes_at, entry_fee_cc, entry_fee_kwacha,
    prize_1st_cc, prize_2nd_cc, prize_3rd_cc, participation_reward_cc,
    streak_reward_cc, prize_config, is_featured, banner_url, entry_promo_code,
    is_promo, platform_hosted, published_at, created_by)
  VALUES (
    COALESCE(NULLIF(p_payload->>'host_tenant_id', ''), v_tid, 'coa_platform'),
    v_host,
    NULL,
    NULLIF(p_payload->>'question_set_id', '')::uuid,
    COALESCE(NULLIF(p_payload->>'title', ''), 'Untitled Tournament'),
    p_payload->>'description',
    COALESCE(NULLIF(p_payload->>'format', ''), 'knockout'),
    COALESCE(NULLIF(p_payload->>'visibility', ''), 'public'),
    COALESCE((p_payload->>'allow_host_plays')::boolean, true),
    COALESCE(NULLIF(p_payload->>'max_participants', '')::int, 32),
    COALESCE(NULLIF(p_payload->>'question_count', '')::int, 10),
    COALESCE(NULLIF(p_payload->>'time_per_question', '')::int, 15),
    v_start,
    v_end,
    COALESCE(NULLIF(p_payload->>'status', ''),
             CASE WHEN v_start IS NULL THEN 'draft' ELSE 'scheduled' END),
    p_payload->>'season_label',
    v_weeks,
    v_months,
    COALESCE(NULLIF(p_payload->>'recurrence', ''), 'none'),
    COALESCE(NULLIF(p_payload->>'recurrence_interval', '')::int, 1),
    NULLIF(p_payload->>'recurrence_until', '')::timestamptz,
    NULLIF(p_payload->>'registration_opens_at', '')::timestamptz,
    NULLIF(p_payload->>'registration_closes_at', '')::timestamptz,
    COALESCE(NULLIF(p_payload->>'entry_fee_cc', '')::int, 0),
    COALESCE(NULLIF(p_payload->>'entry_fee_kwacha', '')::numeric, 0),
    COALESCE(NULLIF(p_payload->>'prize_1st_cc', '')::int, 0),
    COALESCE(NULLIF(p_payload->>'prize_2nd_cc', '')::int, 0),
    COALESCE(NULLIF(p_payload->>'prize_3rd_cc', '')::int, 0),
    COALESCE(NULLIF(p_payload->>'participation_reward_cc', '')::int, 0),
    COALESCE(NULLIF(p_payload->>'streak_reward_cc', '')::int, 0),
    COALESCE(p_payload->'prize_config', '{}'::jsonb),
    COALESCE((p_payload->>'is_featured')::boolean, false),
    p_payload->>'banner_url',
    p_payload->>'entry_promo_code',
    COALESCE((p_payload->>'is_promo')::boolean, false),
    true,
    CASE WHEN (p_payload->>'publish')::boolean THEN now() ELSE NULL END,
    v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('tournament_id', v_id, 'ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_quiz_tournament_admin(jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_quiz_tournament_admin(jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.create_quiz_tournament_admin(jsonb) TO authenticated;

-- ── 5. Update (staff) — allow-listed dynamic SET ────────────────────────────
CREATE OR REPLACE FUNCTION public.update_quiz_tournament_admin(
  p_tournament_id uuid,
  p_payload       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_set  text := 'updated_at = now()';
  v_spec text;
  v_col  text;
  v_type text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_tournaments WHERE id = p_tournament_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  FOREACH v_spec IN ARRAY ARRAY[
    'title:text', 'description:text', 'format:text', 'visibility:text',
    'question_count:int', 'time_per_question:int', 'max_participants:int',
    'allow_host_plays:boolean', 'question_set_id:uuid', 'status:text',
    'starts_at:timestamptz', 'ends_at:timestamptz',
    'season_label:text', 'duration_weeks:int', 'duration_months:int',
    'recurrence:text', 'recurrence_interval:int', 'recurrence_until:timestamptz',
    'registration_opens_at:timestamptz', 'registration_closes_at:timestamptz',
    'entry_fee_cc:int', 'entry_fee_kwacha:numeric',
    'prize_1st_cc:int', 'prize_2nd_cc:int', 'prize_3rd_cc:int',
    'participation_reward_cc:int', 'streak_reward_cc:int',
    'prize_config:jsonb', 'is_featured:boolean', 'banner_url:text',
    'entry_promo_code:text', 'is_promo:boolean', 'cancelled_reason:text'
  ] LOOP
    v_col  := split_part(v_spec, ':', 1);
    v_type := split_part(v_spec, ':', 2);
    IF p_payload ? v_col THEN
      v_set := v_set || format(', %I = ($1->>%L)::%s', v_col, v_col, v_type);
    END IF;
  END LOOP;

  EXECUTE format(
    'UPDATE public.quiz_tournaments SET %s WHERE id = $2', v_set)
    USING p_payload, p_tournament_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_quiz_tournament_admin(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_quiz_tournament_admin(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.update_quiz_tournament_admin(uuid, jsonb) TO authenticated;

-- ── 6. Publish / feature / cancel / duplicate ───────────────────────────────
CREATE OR REPLACE FUNCTION public.publish_quiz_tournament(
  p_tournament_id uuid,
  p_publish       boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  UPDATE public.quiz_tournaments
     SET published_at = CASE WHEN p_publish THEN now() ELSE NULL END,
         status = CASE WHEN p_publish AND status = 'draft' THEN 'scheduled' ELSE status END
   WHERE id = p_tournament_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'published', p_publish);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.publish_quiz_tournament(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.publish_quiz_tournament(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.publish_quiz_tournament(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_quiz_tournament_featured(
  p_tournament_id uuid,
  p_featured      boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  UPDATE public.quiz_tournaments SET is_featured = p_featured
   WHERE id = p_tournament_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'is_featured', p_featured);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_quiz_tournament_featured(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_quiz_tournament_featured(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.set_quiz_tournament_featured(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_quiz_tournament_admin(
  p_tournament_id uuid,
  p_reason        text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  UPDATE public.quiz_tournaments
     SET status = 'cancelled', cancelled_reason = p_reason, is_featured = false
   WHERE id = p_tournament_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_quiz_tournament_admin(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.cancel_quiz_tournament_admin(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.cancel_quiz_tournament_admin(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_quiz_tournament(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_base jsonb;
  v_new  jsonb;
  v_id   uuid;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  SELECT to_jsonb(t) INTO v_base FROM public.quiz_tournaments t
   WHERE t.id = p_tournament_id;
  IF v_base IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  v_new := (v_base
    - 'id' - 'created_at' - 'updated_at' - 'published_at')
    || jsonb_build_object(
         'id', gen_random_uuid(),
         'title', COALESCE(v_base->>'title', 'Tournament') || ' (Copy)',
         'status', 'draft',
         'is_featured', false,
         'created_at', now(),
         'updated_at', now(),
         'created_by', v_uid);

  INSERT INTO public.quiz_tournaments
  SELECT * FROM jsonb_populate_record(NULL::public.quiz_tournaments, v_new)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'tournament_id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.duplicate_quiz_tournament(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.duplicate_quiz_tournament(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.duplicate_quiz_tournament(uuid) TO authenticated;

-- ── 7. Recurrence: spawn the next N occurrences ─────────────────────────────
CREATE OR REPLACE FUNCTION public.spawn_quiz_tournament_occurrences(
  p_tournament_id uuid,
  p_count         int DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_base      jsonb;
  v_cur       record;
  v_next      jsonb;
  v_id        uuid;
  v_ids       uuid[] := ARRAY[]::uuid[];
  v_i         int;
  v_start     timestamptz;
  v_end       timestamptz;
  v_step      interval;
  v_step_days int;
  v_recur     text;
  v_interval  int;
  v_len       interval;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  SELECT to_jsonb(t), t.recurrence, t.recurrence_interval, t.starts_at, t.ends_at
    INTO v_base, v_recur, v_interval, v_start, v_end
    FROM public.quiz_tournaments t WHERE t.id = p_tournament_id;
  IF v_base IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_recur IS NULL OR v_recur = 'none' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_recurrence');
  END IF;

  v_step := CASE v_recur
    WHEN 'daily'   THEN make_interval(days => v_interval)
    WHEN 'weekly'  THEN make_interval(weeks => v_interval)
    WHEN 'monthly' THEN make_interval(months => v_interval)
    WHEN 'yearly'  THEN make_interval(months => 12 * v_interval)
    ELSE make_interval(weeks => v_interval)
  END;
  v_len := CASE WHEN v_start IS NOT NULL AND v_end IS NOT NULL
                THEN v_end - v_start ELSE interval '0' END;

  FOR v_i IN 1..GREATEST(LEAST(COALESCE(p_count, 3), 24), 1) LOOP
    v_base := v_base || jsonb_build_object(
      'id', gen_random_uuid(),
      'starts_at', v_start + (v_step * v_i),
      'ends_at', v_start + (v_step * v_i) + v_len,
      'title', regexp_replace(COALESCE(v_base->>'title', 'Tournament'),
                              '\s*#' || (v_i) || '$', '')
              || ' #' || (v_i + 1),
      'status', 'draft',
      'is_featured', false,
      'created_at', now(),
      'updated_at', now(),
      'created_by', v_uid
    );

    INSERT INTO public.quiz_tournaments
    SELECT * FROM jsonb_populate_record(NULL::public.quiz_tournaments, v_base)
    RETURNING id INTO v_id;

    v_ids := v_ids || v_id;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'spawned', v_ids);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.spawn_quiz_tournament_occurrences(uuid, int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.spawn_quiz_tournament_occurrences(uuid, int) FROM public;
GRANT EXECUTE ON FUNCTION public.spawn_quiz_tournament_occurrences(uuid, int) TO authenticated;

-- ── 8. Auto-award on completion (idempotent, server-side) ───────────────────
CREATE OR REPLACE FUNCTION public.award_quiz_tournament_prizes(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t          public.quiz_tournaments%rowtype;
  v_p1         int;
  v_p2         int;
  v_p3         int;
  v_part       int;
  v_streak     int;
  v_streak_min int;
  v_row        record;
  v_award_id   uuid;
  v_awarded    int := 0;
  v_cc         int;
  v_type       text;
  v_rank       int;
  v_total      int := 0;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  SELECT * INTO v_t FROM public.quiz_tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  -- Per-tournament prizes, falling back to remote-config defaults.
  v_p1 := v_t.prize_1st_cc;
  v_p2 := v_t.prize_2nd_cc;
  v_p3 := v_t.prize_3rd_cc;
  v_part := v_t.participation_reward_cc;
  v_streak := v_t.streak_reward_cc;
  IF v_p1 = 0 AND v_p2 = 0 AND v_p3 = 0 THEN
    SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                      WHERE key = 'quiz_prize_1st_cc' LIMIT 1), 500)::int INTO v_p1;
    SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                      WHERE key = 'quiz_prize_2nd_cc' LIMIT 1), 300)::int INTO v_p2;
    SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                      WHERE key = 'quiz_prize_3rd_cc' LIMIT 1), 150)::int INTO v_p3;
  END IF;
  v_streak_min := COALESCE(NULLIF(v_t.prize_config->>'streak_min_correct', '')::int, 1);

  -- Prize winners (rank by score, then correct answers, then earliest entry).
  FOR v_row IN
    SELECT user_id,
           row_number() OVER (
             ORDER BY score DESC, correct_count DESC, created_at ASC)::int AS rnk
      FROM public.quiz_tournament_participants
     WHERE tournament_id = p_tournament_id
       AND status <> 'withdrawn'
  LOOP
    v_rank := v_row.rnk;
    v_cc := CASE v_rank WHEN 1 THEN v_p1 WHEN 2 THEN v_p2 WHEN 3 THEN v_p3 ELSE 0 END;

    IF v_cc > 0 THEN
      INSERT INTO public.quiz_tournament_awards
        (tournament_id, user_id, rank, award_type, cc_amount, label, awarded_by)
      VALUES (p_tournament_id, v_row.user_id, v_rank, 'prize', v_cc,
              'Tournament prize #' || v_rank, auth.uid())
      ON CONFLICT (tournament_id, user_id, award_type) DO NOTHING
      RETURNING id INTO v_award_id;

      IF v_award_id IS NOT NULL THEN
        v_awarded := v_awarded + 1;
        v_total := v_total + v_cc;
        UPDATE public.profiles
           SET coins = COALESCE(coins, 0) + v_cc,
               balance_cc = COALESCE(balance_cc, 0) + v_cc
         WHERE id = v_row.user_id;
        INSERT INTO public.coin_redemptions
          (user_id, amount, redemption_type, description, status)
        VALUES (v_row.user_id, v_cc, 'quiz_tournament_prize',
                'Quiz tournament prize #' || v_rank || ' — ' || v_t.title,
                'completed');
        INSERT INTO public.notifications (user_id, title, body)
        VALUES (v_row.user_id, 'Quiz Tournament Reward',
                'You finished #' || v_rank || ' in ' || v_t.title ||
                ' and earned ' || v_cc || ' Church Coins!');
      END IF;
      v_award_id := NULL;
    END IF;
  END LOOP;

  -- Participation reward (everyone who played).
  IF v_part > 0 THEN
    FOR v_row IN
      SELECT user_id FROM public.quiz_tournament_participants
       WHERE tournament_id = p_tournament_id AND status <> 'withdrawn'
    LOOP
      INSERT INTO public.quiz_tournament_awards
        (tournament_id, user_id, rank, award_type, cc_amount, label, awarded_by)
      VALUES (p_tournament_id, v_row.user_id, NULL, 'participation', v_part,
              'Participation reward', auth.uid())
      ON CONFLICT (tournament_id, user_id, award_type) DO NOTHING
      RETURNING id INTO v_award_id;

      IF v_award_id IS NOT NULL THEN
        v_awarded := v_awarded + 1;
        v_total := v_total + v_part;
        UPDATE public.profiles
           SET coins = COALESCE(coins, 0) + v_part,
               balance_cc = COALESCE(balance_cc, 0) + v_part
         WHERE id = v_row.user_id;
        INSERT INTO public.coin_redemptions
          (user_id, amount, redemption_type, description, status)
        VALUES (v_row.user_id, v_part, 'quiz_tournament_reward',
                'Participation reward — ' || v_t.title, 'completed');
      END IF;
      v_award_id := NULL;
    END LOOP;
  END IF;

  -- Streak reward (configurable correct-answer threshold).
  IF v_streak > 0 THEN
    FOR v_row IN
      SELECT user_id FROM public.quiz_tournament_participants
       WHERE tournament_id = p_tournament_id
         AND status <> 'withdrawn'
         AND correct_count >= GREATEST(v_streak_min, 1)
    LOOP
      INSERT INTO public.quiz_tournament_awards
        (tournament_id, user_id, rank, award_type, cc_amount, label, awarded_by)
      VALUES (p_tournament_id, v_row.user_id, NULL, 'streak', v_streak,
              'Consistency reward', auth.uid())
      ON CONFLICT (tournament_id, user_id, award_type) DO NOTHING
      RETURNING id INTO v_award_id;

      IF v_award_id IS NOT NULL THEN
        v_awarded := v_awarded + 1;
        v_total := v_total + v_streak;
        UPDATE public.profiles
           SET coins = COALESCE(coins, 0) + v_streak,
               balance_cc = COALESCE(balance_cc, 0) + v_streak
         WHERE id = v_row.user_id;
        INSERT INTO public.coin_redemptions
          (user_id, amount, redemption_type, description, status)
        VALUES (v_row.user_id, v_streak, 'quiz_tournament_reward',
                'Consistency reward — ' || v_t.title, 'completed');
      END IF;
      v_award_id := NULL;
    END LOOP;
  END IF;

  UPDATE public.quiz_tournaments
     SET status = 'completed',
         ends_at = COALESCE(ends_at, now()),
         is_featured = false
   WHERE id = p_tournament_id;

  RETURN jsonb_build_object('ok', true, 'awarded', v_awarded,
                            'total_cc', v_total);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.award_quiz_tournament_prizes(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.award_quiz_tournament_prizes(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.award_quiz_tournament_prizes(uuid) TO authenticated;

-- ── 9. Manual award / revoke (staff) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_tournament_reward_manual(
  p_tournament_id uuid,
  p_user_id       uuid,
  p_cc            int DEFAULT 0,
  p_promo_code    text DEFAULT NULL,
  p_label         text DEFAULT 'Manual reward',
  p_rank          int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_old     public.quiz_tournament_awards%rowtype;
  v_delta   int;
  v_award   uuid;
  v_title   text;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user required'; END IF;

  SELECT title INTO v_title FROM public.quiz_tournaments WHERE id = p_tournament_id;
  IF v_title IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  SELECT * INTO v_old FROM public.quiz_tournament_awards
   WHERE tournament_id = p_tournament_id AND user_id = p_user_id
     AND award_type = 'manual' FOR UPDATE;

  IF FOUND THEN
    IF v_old.status = 'awarded' THEN
      v_delta := COALESCE(p_cc, 0) - v_old.cc_amount;
      IF v_delta <> 0 THEN
        UPDATE public.profiles
           SET coins = GREATEST(COALESCE(coins, 0) + v_delta, 0),
               balance_cc = GREATEST(COALESCE(balance_cc, 0) + v_delta, 0)
         WHERE id = p_user_id;
      END IF;
    ELSE
      -- Was revoked; re-grant the full amount.
      IF COALESCE(p_cc, 0) > 0 THEN
        UPDATE public.profiles
           SET coins = COALESCE(coins, 0) + p_cc,
               balance_cc = COALESCE(balance_cc, 0) + p_cc
         WHERE id = p_user_id;
      END IF;
    END IF;

    UPDATE public.quiz_tournament_awards
       SET cc_amount = COALESCE(p_cc, 0), promo_code = p_promo_code,
           label = p_label, rank = p_rank, status = 'awarded',
           awarded_by = v_uid, awarded_at = now(),
           revoked_by = NULL, revoked_at = NULL
     WHERE id = v_old.id
     RETURNING id INTO v_award;

    RETURN jsonb_build_object('ok', true, 'award_id', v_award, 'updated', true);
  END IF;

  INSERT INTO public.quiz_tournament_awards
    (tournament_id, user_id, rank, award_type, cc_amount, promo_code, label,
     awarded_by)
  VALUES (p_tournament_id, p_user_id, p_rank, 'manual', COALESCE(p_cc, 0),
          p_promo_code, p_label, v_uid)
  RETURNING id INTO v_award;

  IF COALESCE(p_cc, 0) > 0 THEN
    UPDATE public.profiles
       SET coins = COALESCE(coins, 0) + p_cc,
           balance_cc = COALESCE(balance_cc, 0) + p_cc
     WHERE id = p_user_id;
    INSERT INTO public.coin_redemptions
      (user_id, amount, redemption_type, description, status)
    VALUES (p_user_id, p_cc, 'quiz_tournament_reward',
            COALESCE(p_label, 'Manual reward') || ' — ' || v_title, 'completed');
  END IF;

  INSERT INTO public.notifications (user_id, title, body)
  VALUES (p_user_id, 'Quiz Reward',
          'You received ' || COALESCE(p_cc, 0) || ' Church Coins'
          || CASE WHEN p_promo_code IS NOT NULL
                  THEN ' and a promo code (' || p_promo_code || ')'
                  ELSE '' END
          || ' — ' || COALESCE(p_label, '') || '.');

  RETURN jsonb_build_object('ok', true, 'award_id', v_award);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.award_tournament_reward_manual(uuid, uuid, int, text, text, int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.award_tournament_reward_manual(uuid, uuid, int, text, text, int) FROM public;
GRANT EXECUTE ON FUNCTION public.award_tournament_reward_manual(uuid, uuid, int, text, text, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_tournament_award(p_award_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_award public.quiz_tournament_awards%rowtype;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  SELECT * INTO v_award FROM public.quiz_tournament_awards
   WHERE id = p_award_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_award.status <> 'awarded' THEN
    RETURN jsonb_build_object('ok', true, 'already_revoked', true);
  END IF;

  IF v_award.cc_amount > 0 THEN
    UPDATE public.profiles
       SET coins = GREATEST(COALESCE(coins, 0) - v_award.cc_amount, 0),
           balance_cc = GREATEST(COALESCE(balance_cc, 0) - v_award.cc_amount, 0)
     WHERE id = v_award.user_id;
    INSERT INTO public.coin_redemptions
      (user_id, amount, redemption_type, description, status)
    VALUES (v_award.user_id, v_award.cc_amount, 'quiz_tournament_reward_revoke',
            'Reward revoked', 'completed');
  END IF;

  UPDATE public.quiz_tournament_awards
     SET status = 'revoked', revoked_by = v_uid, revoked_at = now()
   WHERE id = p_award_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.revoke_tournament_award(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.revoke_tournament_award(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.revoke_tournament_award(uuid) TO authenticated;

-- ── 10. Staff list helpers ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_quiz_tournament_awards(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(row_to_json(a) ORDER BY a.rank NULLS LAST, a.awarded_at), '[]'::jsonb)
    FROM (
      SELECT aw.id, aw.tournament_id, aw.user_id, aw.rank, aw.award_type,
             aw.cc_amount, aw.promo_code, aw.label, aw.status,
             aw.awarded_at, aw.revoked_at,
             p.full_name, p.avatar_url, p.tenant_id
        FROM public.quiz_tournament_awards aw
        LEFT JOIN public.profiles p ON p.id = aw.user_id
       WHERE aw.tournament_id = p_tournament_id
    ) a;
$$;

REVOKE EXECUTE ON FUNCTION public.list_quiz_tournament_awards(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_quiz_tournament_awards(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.list_quiz_tournament_awards(uuid) TO authenticated;
