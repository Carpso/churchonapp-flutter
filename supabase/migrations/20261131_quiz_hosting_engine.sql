-- ============================================================================
-- 20261131_quiz_hosting_engine.sql
-- Church-hosted Bible quiz tournaments.
--
-- MODEL
--   * A church LEASES the quiz engine (a session/season = a year) — hosting
--     requires an ACTIVE lease. Non-leased churches may still COMPETE.
--   * The lease is AUTO-APPROVED the moment a confirmed `coa_payments` row
--     covers the lease fee — no manual COA click needed (COA can still revoke).
--   * The quiz master uploads their own question paper (PDF/DOC/TXT/CSV). The
--     file is archived to R2 (`quiz-questions/`), text is extracted and parsed
--     into `quiz_set_questions` by the `quiz-import` Edge Function.
--   * The HOST controls the study pack: participants study on-app by default;
--     the host can hide specific questions/whole sets until a round starts.
--   * A tournament's audience is: the host tenant + invited tenants + optional
--     PUBLIC flag. The HOST also competes against its invited tenants — including
--     invited tenants that never leased (they compete, only the host pays).
-- ============================================================================

-- ── 1. Engine leases ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.quiz_engine_leases (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      text NOT NULL,
  plan           text NOT NULL DEFAULT 'season',     -- season | annual
  season_label   text,
  starts_at      timestamptz NOT NULL DEFAULT now(),
  ends_at        timestamptz NOT NULL,
  fee_kwacha     numeric NOT NULL DEFAULT 0,
  payment_ref    text,
  status         text NOT NULL DEFAULT 'pending',    -- pending | active | expired | revoked
  auto_approved  boolean NOT NULL DEFAULT false,
  approved_at    timestamptz,
  approved_by    uuid,
  revoked_reason text,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_leases_tenant
  ON public.quiz_engine_leases (tenant_id, status, ends_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_quiz_leases_active_per_tenant
  ON public.quiz_engine_leases (tenant_id)
  WHERE status = 'active';

ALTER TABLE public.quiz_engine_leases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_leases_tenant_read" ON public.quiz_engine_leases;
CREATE POLICY "quiz_leases_tenant_read"
  ON public.quiz_engine_leases FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );
-- Writes only via the SECURITY DEFINER RPC below (no client INSERT/UPDATE).

-- ── 2. Question sets (uploaded by the quiz master) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.quiz_question_sets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        text NOT NULL,
  lease_id         uuid REFERENCES public.quiz_engine_leases(id) ON DELETE SET NULL,
  title            text NOT NULL,
  description      text,
  source_file_url  text,          -- R2 object
  source_file_name text,
  source_file_type text,          -- pdf | docx | txt | csv
  extract_status   text NOT NULL DEFAULT 'pending', -- pending|processing|ready|failed
  extract_error    text,
  extracted_count  int NOT NULL DEFAULT 0,
  -- Study-pack policy. true = participants may read questions in-app before
  -- the tournament; false = hidden until the round starts. Per-question
  -- overrides live on `quiz_set_questions.is_study_visible`.
  study_pack_open  boolean NOT NULL DEFAULT true,
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_sets_tenant
  ON public.quiz_question_sets (tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.quiz_set_questions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id           uuid NOT NULL REFERENCES public.quiz_question_sets(id) ON DELETE CASCADE,
  tenant_id        text NOT NULL,
  book             text,
  chapter          int,
  verse            int,
  verse_reference  text,
  category         text,           -- directQuote | chapterAnalysis | multipleChoice | speedRound
  difficulty       text,           -- easy | medium | hard
  prompt           text NOT NULL,
  options          jsonb NOT NULL DEFAULT '[]'::jsonb,
  correct_answers  jsonb NOT NULL DEFAULT '[]'::jsonb,
  explanation      text,
  points           int NOT NULL DEFAULT 10,
  is_study_visible boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_set_questions_set
  ON public.quiz_set_questions (set_id);

ALTER TABLE public.quiz_question_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_set_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_sets_owner_read" ON public.quiz_question_sets;
CREATE POLICY "quiz_sets_owner_read"
  ON public.quiz_question_sets FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- Questions: the owning tenant sees everything (incl. hidden ones). A
-- PARTICIPANT of a tournament that uses the set sees only what the study-pack
-- policy exposes.
DROP POLICY IF EXISTS "quiz_set_questions_owner_read" ON public.quiz_set_questions;
CREATE POLICY "quiz_set_questions_owner_read"
  ON public.quiz_set_questions FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

DROP POLICY IF EXISTS "quiz_set_questions_study_pack_read" ON public.quiz_set_questions;

-- ── 3. Tournaments ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.quiz_tournaments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_tenant_id    text NOT NULL,
  host_user_id      uuid,
  lease_id          uuid REFERENCES public.quiz_engine_leases(id) ON DELETE SET NULL,
  question_set_id   uuid REFERENCES public.quiz_question_sets(id) ON DELETE SET NULL,
  title             text NOT NULL,
  description       text,
  format            text NOT NULL DEFAULT 'knockout', -- knockout | roundRobin | single
  visibility        text NOT NULL DEFAULT 'tenant',   -- tenant | invited | public
  allow_host_plays  boolean NOT NULL DEFAULT true,    -- host competes too
  max_participants  int NOT NULL DEFAULT 32,
  question_count    int NOT NULL DEFAULT 10,
  time_per_question int NOT NULL DEFAULT 15,
  starts_at         timestamptz,
  ends_at           timestamptz,
  status            text NOT NULL DEFAULT 'draft',    -- draft|scheduled|live|completed|cancelled
  created_by        uuid,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_tournaments_host
  ON public.quiz_tournaments (host_tenant_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_quiz_tournaments_live
  ON public.quiz_tournaments (status, visibility);

CREATE TABLE IF NOT EXISTS public.quiz_tournament_invites (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.quiz_tournaments(id) ON DELETE CASCADE,
  tenant_id      text NOT NULL,
  invited_by     uuid,
  status         text NOT NULL DEFAULT 'invited',   -- invited | accepted | declined
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, tenant_id)
);

CREATE TABLE IF NOT EXISTS public.quiz_tournament_participants (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.quiz_tournaments(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL,
  tenant_id      text,
  team_name      text,
  seed           int,
  score          int NOT NULL DEFAULT 0,
  correct_count  int NOT NULL DEFAULT 0,
  status         text NOT NULL DEFAULT 'registered', -- registered|eliminated|winner|withdrawn
  is_host_side   boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_quiz_tpart_tournament
  ON public.quiz_tournament_participants (tournament_id, score DESC);

-- Bracket / round matches. `match_id` links to the live PvP realtime match so
-- the existing arena + spectator plumbing is reused.
CREATE TABLE IF NOT EXISTS public.quiz_tournament_matches (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.quiz_tournaments(id) ON DELETE CASCADE,
  round          int NOT NULL DEFAULT 1,
  slot           int NOT NULL DEFAULT 1,
  home_user_id   uuid,
  away_user_id   uuid,
  home_score     int,
  away_score     int,
  winner_user_id uuid,
  match_id       uuid,                    -- -> pvp_matches.id (live play)
  status         text NOT NULL DEFAULT 'pending', -- pending|live|completed|bye
  started_at     timestamptz,
  completed_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_tmatches_tournament
  ON public.quiz_tournament_matches (tournament_id, round, slot);

-- Spectator counter (non-participating members watching).
CREATE TABLE IF NOT EXISTS public.quiz_tournament_viewers (
  tournament_id uuid NOT NULL REFERENCES public.quiz_tournaments(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  last_seen     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tournament_id, user_id)
);

ALTER TABLE public.quiz_tournaments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_tournament_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_tournament_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_tournament_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_tournament_viewers ENABLE ROW LEVEL SECURITY;

-- Tournaments readable when: host tenant, invited tenant, participant, public,
-- or platform staff.
DROP POLICY IF EXISTS "quiz_tournaments_read" ON public.quiz_tournaments;
CREATE POLICY "quiz_tournaments_read"
  ON public.quiz_tournaments FOR SELECT TO authenticated
  USING (
    visibility = 'public'
    OR host_tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.quiz_tournament_invites i
      WHERE i.tournament_id = quiz_tournaments.id
        AND i.tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.quiz_tournament_participants tp
      WHERE tp.tournament_id = quiz_tournaments.id AND tp.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

DROP POLICY IF EXISTS "quiz_tinvites_read" ON public.quiz_tournament_invites;
CREATE POLICY "quiz_tinvites_read"
  ON public.quiz_tournament_invites FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.quiz_tournaments t
      WHERE t.id = quiz_tournament_invites.tournament_id
        AND t.host_tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "quiz_tparticipants_read" ON public.quiz_tournament_participants;
CREATE POLICY "quiz_tparticipants_read"
  ON public.quiz_tournament_participants FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.quiz_tournaments t
      WHERE t.id = quiz_tournament_participants.tournament_id
        AND (
          t.visibility = 'public'
          OR t.host_tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
          OR EXISTS (
            SELECT 1 FROM public.quiz_tournament_invites i
            WHERE i.tournament_id = t.id
              AND i.tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
          )
        )
    )
  );

DROP POLICY IF EXISTS "quiz_tmatches_read" ON public.quiz_tournament_matches;
CREATE POLICY "quiz_tmatches_read"
  ON public.quiz_tournament_matches FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.quiz_tournaments t
      WHERE t.id = quiz_tournament_matches.tournament_id
        AND (
          t.visibility = 'public'
          OR t.host_tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
          OR EXISTS (
            SELECT 1 FROM public.quiz_tournament_invites i
            WHERE i.tournament_id = t.id
              AND i.tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
          )
        )
    )
  );

-- Viewers: you may only see/record your own presence.
DROP POLICY IF EXISTS "quiz_tviewers_own" ON public.quiz_tournament_viewers;
CREATE POLICY "quiz_tviewers_own"
  ON public.quiz_tournament_viewers FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── 3b. Study-pack read policy (declared after all tables exist) ────────────
DROP POLICY IF EXISTS "quiz_set_questions_study_pack_read" ON public.quiz_set_questions;
CREATE POLICY "quiz_set_questions_study_pack_read"
  ON public.quiz_set_questions FOR SELECT TO authenticated
  USING (
    is_study_visible
    AND EXISTS (
      SELECT 1
      FROM public.quiz_question_sets s
      JOIN public.quiz_tournaments t ON t.question_set_id = s.id
      JOIN public.quiz_tournament_participants tp ON tp.tournament_id = t.id
      WHERE s.id = quiz_set_questions.set_id
        AND tp.user_id = auth.uid()
        AND s.study_pack_open
    )
  );

-- ── 4. Auto-approved engine lease ───────────────────────────────────────────
-- A lease is granted automatically as soon as a CONFIRMED coa_payments row
-- covers the fee (no manual COA action). Amounts are re-derived server-side
-- from platform_settings — the client never states a price.
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
  v_uid        uuid := auth.uid();
  v_tid        text;
  v_role       text;
  v_fee        numeric := 0;
  v_days       int := 365;
  v_paid       numeric := 0;
  v_lease_id   uuid;
  v_existing   public.quiz_engine_leases%rowtype;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id, role INTO v_tid, v_role
    FROM public.profiles WHERE id = v_uid;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'no tenant';
  END IF;

  IF v_role NOT IN ('superadmin', 'super_admin', 'coa_employee', 'employee',
                    'bishop', 'apostle', 'prophet', 'general_secretary',
                    'pastor', 'admin', 'leader', 'department_leader') THEN
    RAISE EXCEPTION 'not authorised to lease the quiz engine';
  END IF;

  -- Already leased?
  SELECT * INTO v_existing
    FROM public.quiz_engine_leases
   WHERE tenant_id = v_tid AND status = 'active' AND ends_at > now()
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('leased', true, 'already_active', true,
                              'lease_id', v_existing.id,
                              'ends_at', v_existing.ends_at);
  END IF;

  -- Server-side price + season length.
  SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                    WHERE key = 'quiz_engine_lease_kwacha' LIMIT 1), 1500)
    INTO v_fee;
  SELECT COALESCE((SELECT value::int FROM public.platform_settings
                    WHERE key = 'quiz_engine_lease_days' LIMIT 1), 365)
    INTO v_days;

  -- Confirm payment from the ledger (approved/completed/confirmed/settled).
  SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM public.coa_payments
   WHERE user_id = v_uid
     AND status IN ('approved', 'completed', 'confirmed', 'settled')
     AND amount >= v_fee
     AND (p_payment_ref IS NULL OR payment_ref = p_payment_ref)
     AND created_at > now() - interval '90 days';

  IF v_paid < v_fee THEN
    RETURN jsonb_build_object('leased', false, 'reason', 'payment_required',
                              'fee_kwacha', v_fee, 'paid', v_paid);
  END IF;

  INSERT INTO public.quiz_engine_leases
    (tenant_id, plan, season_label, starts_at, ends_at, fee_kwacha,
     payment_ref, status, auto_approved, approved_at, approved_by, created_by)
  VALUES
    (v_tid, 'season', p_season_label, now(), now() + make_interval(days => v_days),
     v_fee, p_payment_ref, 'active', true, now(), v_uid, v_uid)
  RETURNING id INTO v_lease_id;

  RETURN jsonb_build_object('leased', true, 'lease_id', v_lease_id,
                            'fee_kwacha', v_fee,
                            'ends_at', now() + make_interval(days => v_days));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.lease_quiz_engine(text, text) FROM anon;

-- Helper: is this tenant allowed to host right now?
CREATE OR REPLACE FUNCTION public.tenant_can_host_quiz(p_tenant_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.quiz_engine_leases l
    WHERE l.tenant_id = p_tenant_id
      AND l.status = 'active'
      AND l.ends_at > now()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.tenant_can_host_quiz(text) FROM anon;

-- ── 5. Create a tournament (lease-gated) ────────────────────────────────────
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
  v_uid      uuid := auth.uid();
  v_tid      text;
  v_role     text;
  v_lease    uuid;
  v_id       uuid;
  v_t        text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id, role INTO v_tid, v_role
    FROM public.profiles WHERE id = v_uid;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'no tenant';
  END IF;

  IF v_role NOT IN ('superadmin', 'super_admin', 'coa_employee', 'employee',
                    'bishop', 'apostle', 'prophet', 'general_secretary',
                    'pastor', 'admin', 'leader', 'department_leader') THEN
    RAISE EXCEPTION 'not authorised to host';
  END IF;

  -- HOSTING REQUIRES AN ACTIVE LEASE.
  SELECT id INTO v_lease FROM public.quiz_engine_leases
   WHERE tenant_id = v_tid AND status = 'active' AND ends_at > now()
   LIMIT 1;
  IF v_lease IS NULL THEN
    RAISE EXCEPTION 'lease_required';
  END IF;

  IF p_visibility NOT IN ('tenant', 'invited', 'public') THEN
    RAISE EXCEPTION 'invalid visibility';
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

  -- The HOST also competes (host vs its invited tenants).
  INSERT INTO public.quiz_tournament_participants
    (tournament_id, user_id, tenant_id, team_name, is_host_side)
  VALUES (v_id, v_uid, v_tid, 'Host', true)
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  -- Invited tenants compete even if they never leased (only the host pays).
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

-- ── 6. Join a tournament (host + invited tenants + public) ──────────────────
CREATE OR REPLACE FUNCTION public.join_quiz_tournament(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_t    public.quiz_tournaments%rowtype;
  v_ok   boolean := false;
  v_cnt  int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_t FROM public.quiz_tournaments
   WHERE id = p_tournament_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'not_found');
  END IF;

  IF v_t.status NOT IN ('draft', 'scheduled', 'live') THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'closed');
  END IF;

  v_ok := v_t.visibility = 'public'
       OR v_t.host_tenant_id = v_tid
       OR EXISTS (
            SELECT 1 FROM public.quiz_tournament_invites i
            WHERE i.tournament_id = v_t.id AND i.tenant_id = v_tid
              AND i.status <> 'declined');

  IF NOT v_ok THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'not_invited');
  END IF;

  SELECT count(*) INTO v_cnt FROM public.quiz_tournament_participants
   WHERE tournament_id = v_t.id;
  IF v_cnt >= v_t.max_participants THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'full');
  END IF;

  INSERT INTO public.quiz_tournament_participants
    (tournament_id, user_id, tenant_id, is_host_side)
  VALUES (v_t.id, v_uid, v_tid, v_t.host_tenant_id = v_tid)
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('joined', true, 'tournament_id', v_t.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_quiz_tournament(uuid) FROM anon;

-- ── 7. Spectator presence (non-participating members watching) ──────────────
CREATE OR REPLACE FUNCTION public.quiz_tournament_watch(p_tournament_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_n   int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO public.quiz_tournament_viewers (tournament_id, user_id, last_seen)
  VALUES (p_tournament_id, v_uid, now())
  ON CONFLICT (tournament_id, user_id)
  DO UPDATE SET last_seen = now();

  SELECT count(*) INTO v_n FROM public.quiz_tournament_viewers
   WHERE tournament_id = p_tournament_id
     AND last_seen > now() - interval '45 seconds';

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.quiz_tournament_watch(uuid) FROM anon;

-- ── 8. Seed pricing keys ────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value)
VALUES
  ('quiz_engine_lease_kwacha', '1500'),
  ('quiz_engine_lease_days', '365')
ON CONFLICT (key) DO NOTHING;
