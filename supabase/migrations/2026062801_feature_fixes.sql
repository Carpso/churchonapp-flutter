-- =====================================================
-- Church On App — Feature Fix Migration v2
-- Run this in Supabase SQL Editor (in order)
-- Each section is independent and safe to re-run.
-- =====================================================


-- ============================================================
-- SECTION 1: QUIZ QUESTIONS TABLE + UNIQUE CONSTRAINT
-- ============================================================

CREATE TABLE IF NOT EXISTS quiz_questions (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  question            TEXT NOT NULL,
  options             JSONB NOT NULL DEFAULT '[]',
  correct_answer      INT NOT NULL DEFAULT 0,
  difficulty          TEXT NOT NULL DEFAULT 'Medium',
  category            TEXT NOT NULL DEFAULT 'General',
  scripture_reference TEXT,
  -- Renamed 'style' to 'type' for consistency with seed data and better clarity.
  -- If 'style' column already exists, you might need to run:
  -- ALTER TABLE quiz_questions RENAME COLUMN style TO type;
  -- Or, if 'type' doesn't exist and 'style' does, and you want to keep 'style'
  -- then adjust the seed data to use 'style' instead of 'type'.
  -- For this fix, we assume 'type' is the desired column name.
  -- Adding a column for direct text answers for 'rapid_fire' and 'verbatim' questions.
  "type"              TEXT DEFAULT 'choice',
  correct_text_answer TEXT,
  points              INT NOT NULL DEFAULT 10,
  is_superadmin_only  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on quiz_questions
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read questions
DROP POLICY IF EXISTS "quiz_questions_read" ON quiz_questions;
CREATE POLICY "quiz_questions_read"
  ON quiz_questions FOR SELECT
  TO authenticated USING (true); -- Authenticated users can read all questions

-- Allow superadmin/employee to manage questions
DROP POLICY IF EXISTS "quiz_questions_admin" ON quiz_questions;
CREATE POLICY "quiz_questions_admin"
  ON quiz_questions FOR ALL
  TO authenticated USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('superadmin', 'employee')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('superadmin', 'employee')
    )
  );

-- Add unique constraint only if it doesn't already exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'quiz_questions_question_unique'
      AND conrelid = 'quiz_questions'::regclass
  ) THEN
    ALTER TABLE quiz_questions
      ADD CONSTRAINT quiz_questions_question_unique UNIQUE (question);
  END IF;
END $$;


-- ============================================================
-- SECTION 2: PRE-REGISTRATION COLUMNS ON ride_registrations
-- (Only if the table exists — created by FINAL_MASTER_BACKEND_SYNC.sql)
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'ride_registrations'
  ) THEN
    -- Add pre_registered_name column
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'ride_registrations' AND column_name = 'pre_registered_name'
    ) THEN
      ALTER TABLE ride_registrations ADD COLUMN pre_registered_name TEXT;
    END IF;

    -- Add pre_registered_phone column
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'ride_registrations' AND column_name = 'pre_registered_phone'
    ) THEN
      ALTER TABLE ride_registrations ADD COLUMN pre_registered_phone TEXT;
    END IF;

    -- Add pre_registered_role column
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'ride_registrations' AND column_name = 'pre_registered_role'
    ) THEN
      ALTER TABLE ride_registrations ADD COLUMN pre_registered_role TEXT;
    END IF;
  END IF;
END $$;


-- ============================================================
-- SECTION 3: PRE-REGISTRATIONS TABLE
-- Central store for all pre-registered users (no account yet)
-- ============================================================

CREATE TABLE IF NOT EXISTS pre_registrations (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  full_name      TEXT NOT NULL,
  phone_number   TEXT,
  email          TEXT,
  role           TEXT NOT NULL CHECK (role IN (
                   'driver', 'rider', 'writer', 'usher',
                   'employee', 'event_organizer', 'church'
                 )),
  notes          TEXT,
  onboarded_by   UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  linked_at      TIMESTAMPTZ  -- set when user signs up and phone matches
);

-- ROW LEVEL SECURITY
ALTER TABLE pre_registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pre_registrations_admin_policy" ON pre_registrations;
CREATE POLICY "pre_registrations_admin_policy"
  ON pre_registrations FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('superadmin', 'employee')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role IN ('superadmin', 'employee')
    )
  );

-- INDEX for fast phone-number lookups (account linking on signup)
CREATE INDEX IF NOT EXISTS idx_pre_registrations_phone
  ON pre_registrations(phone_number)
  WHERE linked_at IS NULL;


-- ============================================================
-- SECTION 4: AUTO-LINK TRIGGER
-- When a profile's phone is set, link matching pre-registrations
-- and update their role if they are still 'member'.
-- ============================================================

CREATE OR REPLACE FUNCTION link_pre_registration()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Mark any matching pre-registration as linked
  UPDATE pre_registrations
    SET linked_at = NOW()
  WHERE phone_number = NEW.phone_number
    AND linked_at IS NULL;

  -- Promote profile role if a pre-registration matched
  UPDATE profiles
    SET role = pr.role
  FROM pre_registrations pr
  WHERE pr.phone_number = NEW.phone_number
    AND pr.linked_at IS NOT NULL
    AND profiles.id = NEW.id
    AND profiles.role = 'member';  -- only override default role

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_link_pre_registration ON profiles;
CREATE TRIGGER trg_link_pre_registration
  AFTER INSERT OR UPDATE OF phone_number ON profiles
  FOR EACH ROW
  WHEN (NEW.phone_number IS NOT NULL)
  EXECUTE FUNCTION link_pre_registration();
