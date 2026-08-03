-- Quiz weekly seasons, rewards, and church leasing

-- ── Quiz Seasons (weekly cycles) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quiz_seasons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_name TEXT NOT NULL,
  week_number INT NOT NULL,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure is_active column exists before creating partial index
ALTER TABLE quiz_seasons ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT false;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_quiz_seasons_active') THEN
    CREATE INDEX idx_quiz_seasons_active ON quiz_seasons(is_active) WHERE is_active = true;
  END IF;
END $$;

-- ── Quiz Season Rewards ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quiz_season_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id UUID NOT NULL REFERENCES quiz_seasons(id) ON DELETE CASCADE,
  rank_from INT NOT NULL,
  rank_to INT NOT NULL,
  reward_type TEXT NOT NULL DEFAULT 'coins',
  reward_value INT NOT NULL DEFAULT 0,
  reward_label TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── Weekly leaderboard snapshot (reset per season) ────────────────────────────
CREATE TABLE IF NOT EXISTS quiz_weekly_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id UUID NOT NULL REFERENCES quiz_seasons(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  score INT NOT NULL DEFAULT 0,
  correct_count INT NOT NULL DEFAULT 0,
  total_questions INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(season_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_quiz_weekly_scores_season_score
  ON quiz_weekly_scores(season_id, score DESC);

-- Safely add columns to quiz_seasons if table already existed
ALTER TABLE quiz_seasons ADD COLUMN IF NOT EXISTS week_number INT;
ALTER TABLE quiz_seasons ADD COLUMN IF NOT EXISTS start_date TIMESTAMPTZ;
ALTER TABLE quiz_seasons ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;

-- Ensure is_active column exists BEFORE creating the partial index
ALTER TABLE quiz_seasons ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT false;

-- ── Church Quiz Leases (monthly subscription) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS church_quiz_leases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','expired','cancelled')),
  amount_paid INT NOT NULL DEFAULT 1500,
  currency TEXT NOT NULL DEFAULT 'ZMW',
  lease_start TIMESTAMPTZ,
  lease_end TIMESTAMPTZ,
  payment_reference TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_church_quiz_leases_church ON church_quiz_leases(church_id);
CREATE INDEX IF NOT EXISTS idx_church_quiz_leases_active ON church_quiz_leases(church_id) WHERE status = 'active';

-- ── RLS for quiz seasons ──────────────────────────────────────────────────────
ALTER TABLE quiz_seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_season_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_weekly_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE church_quiz_leases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_seasons_select" ON "quiz_seasons";
CREATE POLICY "quiz_seasons_select" ON "quiz_seasons" FOR SELECT USING (true);
DROP POLICY IF EXISTS "quiz_seasons_insert" ON "quiz_seasons";
CREATE POLICY "quiz_seasons_insert" ON "quiz_seasons" FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
);
DROP POLICY IF EXISTS "quiz_seasons_update" ON "quiz_seasons";
CREATE POLICY "quiz_seasons_update" ON "quiz_seasons" FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
);

DROP POLICY IF EXISTS "quiz_season_rewards_select" ON "quiz_season_rewards";
CREATE POLICY "quiz_season_rewards_select" ON "quiz_season_rewards" FOR SELECT USING (true);
DROP POLICY IF EXISTS "quiz_season_rewards_insert" ON "quiz_season_rewards";
CREATE POLICY "quiz_season_rewards_insert" ON "quiz_season_rewards" FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
);
DROP POLICY IF EXISTS "quiz_season_rewards_update" ON "quiz_season_rewards";
CREATE POLICY "quiz_season_rewards_update" ON "quiz_season_rewards" FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
);

DROP POLICY IF EXISTS "quiz_weekly_scores_select" ON "quiz_weekly_scores";
CREATE POLICY "quiz_weekly_scores_select" ON "quiz_weekly_scores" FOR SELECT USING (true);
DROP POLICY IF EXISTS "quiz_weekly_scores_upsert" ON "quiz_weekly_scores";
CREATE POLICY "quiz_weekly_scores_upsert" ON "quiz_weekly_scores" FOR INSERT WITH CHECK (
  auth.uid() = user_id
);
DROP POLICY IF EXISTS "quiz_weekly_scores_update" ON "quiz_weekly_scores";
CREATE POLICY "quiz_weekly_scores_update" ON "quiz_weekly_scores" FOR UPDATE USING (
  auth.uid() = user_id
);

-- Church lease: church admins see their own lease, superadmin sees all
DROP POLICY IF EXISTS "church_quiz_leases_select" ON "church_quiz_leases";
CREATE POLICY "church_quiz_leases_select" ON "church_quiz_leases" FOR SELECT USING (
  church_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin')
);
DROP POLICY IF EXISTS "church_quiz_leases_insert" ON "church_quiz_leases";
CREATE POLICY "church_quiz_leases_insert" ON "church_quiz_leases" FOR INSERT WITH CHECK (
  church_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
  AND EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop'))
);
DROP POLICY IF EXISTS "church_quiz_leases_update" ON "church_quiz_leases";
CREATE POLICY "church_quiz_leases_update" ON "church_quiz_leases" FOR UPDATE USING (
  church_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
  AND EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop'))
);

-- Helper function: check if a church has an active lease
CREATE OR REPLACE FUNCTION has_active_quiz_lease(church_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM church_quiz_leases
    WHERE church_id = $1 AND status = 'active'
      AND lease_start <= now() AND lease_end >= now()
  );
$$;

-- Function to create or renew a quiz lease after payment
DROP FUNCTION IF EXISTS activate_quiz_lease(UUID, TEXT, INTEGER);
CREATE OR REPLACE FUNCTION activate_quiz_lease(
  p_church_id UUID,
  p_payment_reference TEXT,
  p_amount INT DEFAULT 1500
)
RETURNS church_quiz_leases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lease church_quiz_leases;
BEGIN
  -- Deactivate existing active leases
  UPDATE church_quiz_leases
  SET status = 'expired', updated_at = now()
  WHERE church_id = p_church_id AND status = 'active';

  -- Create new lease (30 days)
  INSERT INTO church_quiz_leases (church_id, status, amount_paid, payment_reference, lease_start, lease_end)
  VALUES (
    p_church_id, 'active', p_amount, p_payment_reference,
    now(), now() + interval '30 days'
  )
  RETURNING * INTO v_lease;

  RETURN v_lease;
END;
$$;

-- Schedule a weekly job to auto-create new quiz seasons (optional)
-- This would be called by a cron trigger or Edge Function
CREATE OR REPLACE FUNCTION create_weekly_quiz_season()
RETURNS quiz_seasons
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last_season quiz_seasons;
  v_new_week INT;
  v_season quiz_seasons;
BEGIN
  SELECT * INTO v_last_season FROM quiz_seasons ORDER BY end_date DESC LIMIT 1;

  v_new_week := COALESCE(v_last_season.week_number, 0) + 1;

  -- Deactivate old seasons
  UPDATE quiz_seasons SET is_active = false WHERE is_active = true;

  INSERT INTO quiz_seasons (season_name, week_number, start_date, end_date, is_active)
  VALUES (
    'Week ' || v_new_week,
    v_new_week,
    date_trunc('week', now()),
    date_trunc('week', now()) + interval '6 days 23:59:59',
    true
  )
  RETURNING * INTO v_season;

  -- Create default rewards for the new season
  INSERT INTO quiz_season_rewards (season_id, rank_from, rank_to, reward_type, reward_value, reward_label) VALUES
    (v_season.id, 1, 1, 'zmw', 500, 'K500'),
    (v_season.id, 2, 2, 'zmw', 300, 'K300'),
    (v_season.id, 3, 3, 'zmw', 150, 'K150'),
    (v_season.id, 4, 10, 'coins', 100, '100 Coins');

  RETURN v_season;
END;
$$;
