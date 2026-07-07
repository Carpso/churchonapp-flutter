-- =====================================================
-- Church On App — Premium Quiz Events & Passes
-- =====================================================

-- QUIZ EVENTS: host church runs a live quiz at a scheduled time
CREATE TABLE IF NOT EXISTS quiz_events (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title           TEXT NOT NULL,
  description     TEXT,
  host_church_id  UUID REFERENCES churches(id) ON DELETE CASCADE,
  created_by      UUID REFERENCES profiles(id) ON DELETE SET NULL,
  pass_price_zmw  NUMERIC(10,2) NOT NULL DEFAULT 0,   -- 0 = free
  pass_price_cc   NUMERIC(10,2) NOT NULL DEFAULT 0,   -- 0 = free
  question_count  INT NOT NULL DEFAULT 10,
  time_per_question_sec INT NOT NULL DEFAULT 15,
  start_time      TIMESTAMPTZ NOT NULL,
  end_time        TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming','active','completed','cancelled')),
  max_participants INT,
  category_filter TEXT,            -- optional category filter
  difficulty_filter TEXT,           -- optional difficulty filter
  is_featured     BOOLEAN NOT NULL DEFAULT FALSE,
  banner_url      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- QUIZ EVENT PARTICIPANTS: who joined, their final score
CREATE TABLE IF NOT EXISTS quiz_event_participants (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_id        UUID REFERENCES quiz_events(id) ON DELETE CASCADE NOT NULL,
  user_id         UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  score           INT NOT NULL DEFAULT 0,
  correct_count   INT NOT NULL DEFAULT 0,
  total_questions INT NOT NULL DEFAULT 0,
  passed_at       TIMESTAMPTZ DEFAULT NOW(),
  completed_at    TIMESTAMPTZ,
  UNIQUE (event_id, user_id)
);

-- QUIZ PASSES: purchase records
CREATE TABLE IF NOT EXISTS quiz_passes (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_id        UUID REFERENCES quiz_events(id) ON DELETE CASCADE NOT NULL,
  user_id         UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  church_id       UUID REFERENCES churches(id) ON DELETE SET NULL,
  payment_method  TEXT,
  payment_ref     TEXT,
  amount_zmw      NUMERIC(10,2) DEFAULT 0,
  amount_cc       NUMERIC(10,2) DEFAULT 0,
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','refunded','cancelled')),
  purchased_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (event_id, user_id)
);

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_quiz_events_status ON quiz_events(status);
CREATE INDEX IF NOT EXISTS idx_quiz_events_start ON quiz_events(start_time);
CREATE INDEX IF NOT EXISTS idx_quiz_events_host ON quiz_events(host_church_id);
CREATE INDEX IF NOT EXISTS idx_quiz_event_participants_event ON quiz_event_participants(event_id);
CREATE INDEX IF NOT EXISTS idx_quiz_event_participants_user ON quiz_event_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_passes_event ON quiz_passes(event_id);
CREATE INDEX IF NOT EXISTS idx_quiz_passes_user ON quiz_passes(user_id);

-- RLS
ALTER TABLE quiz_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_event_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_passes ENABLE ROW LEVEL SECURITY;

-- Anyone can read upcoming/active events
DROP POLICY IF EXISTS "quiz_events_read" ON quiz_events;
CREATE POLICY "quiz_events_read"
  ON quiz_events FOR SELECT
  TO authenticated USING (status IN ('upcoming','active','completed'));

-- Superadmin/employee can manage events
DROP POLICY IF EXISTS "quiz_events_admin" ON quiz_events;
CREATE POLICY "quiz_events_admin"
  ON quiz_events FOR ALL
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  );

-- Participants: read own, insert own
DROP POLICY IF EXISTS "quiz_event_participants_read" ON quiz_event_participants;
CREATE POLICY "quiz_event_participants_read"
  ON quiz_event_participants FOR SELECT
  TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz_event_participants_insert" ON quiz_event_participants;
CREATE POLICY "quiz_event_participants_insert"
  ON quiz_event_participants FOR INSERT
  TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz_event_participants_admin" ON quiz_event_participants;
CREATE POLICY "quiz_event_participants_admin"
  ON quiz_event_participants FOR ALL
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  );

-- Passes: read own, insert own
DROP POLICY IF EXISTS "quiz_passes_read" ON quiz_passes;
CREATE POLICY "quiz_passes_read"
  ON quiz_passes FOR SELECT
  TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz_passes_insert" ON quiz_passes;
CREATE POLICY "quiz_passes_insert"
  ON quiz_passes FOR INSERT
  TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz_passes_admin" ON quiz_passes;
CREATE POLICY "quiz_passes_admin"
  ON quiz_passes FOR ALL
  TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('superadmin','employee'))
  );

-- AUTO-UPDATE updated_at on quiz_events
CREATE OR REPLACE FUNCTION update_quiz_events_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_quiz_events_updated_at ON quiz_events;
CREATE TRIGGER trg_quiz_events_updated_at
  BEFORE UPDATE ON quiz_events
  FOR EACH ROW
  EXECUTE FUNCTION update_quiz_events_updated_at();
