-- Live Streaming tables
CREATE TABLE IF NOT EXISTS live_streams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'live', 'ended')),
  cloudflare_stream_id TEXT,
  stream_url TEXT,
  scheduled_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  viewer_count INTEGER DEFAULT 0,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE live_streams ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "live_streams_select" ON live_streams FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "live_streams_manage" ON live_streams FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin')
      AND church_id = live_streams.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Live stream chat
CREATE TABLE IF NOT EXISTS stream_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  reply_to_id UUID REFERENCES stream_chat_messages(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE stream_chat_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "stream_chat_select" ON stream_chat_messages FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "stream_chat_insert" ON stream_chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Stream prayer requests
CREATE TABLE IF NOT EXISTS stream_prayer_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(stream_id, user_id)
);

ALTER TABLE stream_prayer_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "stream_prayer_select" ON stream_prayer_requests FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "stream_prayer_insert" ON stream_prayer_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "stream_prayer_delete" ON stream_prayer_requests FOR DELETE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Church Websites
CREATE TABLE IF NOT EXISTS church_websites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE UNIQUE,
  title TEXT NOT NULL,
  subtitle TEXT,
  about_text TEXT,
  logo_url TEXT,
  banner_url TEXT,
  primary_color TEXT DEFAULT '#1B5E20',
  contact_phone TEXT,
  contact_email TEXT,
  address TEXT,
  service_times JSONB DEFAULT '{}',
  social_links JSONB DEFAULT '{}',
  sections JSONB DEFAULT '[]',
  is_published BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE church_websites ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "church_websites_public" ON church_websites FOR SELECT USING (is_published = true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "church_websites_manage" ON church_websites FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin')
      AND church_id = church_websites.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Volunteer Scheduling
CREATE TABLE IF NOT EXISTS volunteer_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  ministry TEXT,
  date DATE NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  spots_needed INTEGER DEFAULT 1,
  signed_up_count INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE volunteer_slots ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "volunteer_slots_select" ON volunteer_slots FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "volunteer_slots_manage" ON volunteer_slots FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin')
      AND church_id = volunteer_slots.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Volunteer sign-ups
CREATE TABLE IF NOT EXISTS volunteer_signups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slot_id UUID NOT NULL REFERENCES volunteer_slots(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notes TEXT,
  status TEXT DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(slot_id, user_id)
);

ALTER TABLE volunteer_signups ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "volunteer_signups_select" ON volunteer_signups FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "volunteer_signups_insert" ON volunteer_signups FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "volunteer_signups_update" ON volunteer_signups FOR UPDATE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Sermon Notes (enhanced)
CREATE TABLE IF NOT EXISTS sermon_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sermon_id UUID NOT NULL,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT,
  content TEXT NOT NULL,
  is_ai_generated BOOLEAN DEFAULT false,
  ai_prompt TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE sermon_notes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "sermon_notes_select" ON sermon_notes FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "sermon_notes_insert" ON sermon_notes FOR INSERT WITH CHECK (auth.uid() = author_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "sermon_notes_update" ON sermon_notes FOR UPDATE USING (auth.uid() = author_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "sermon_notes_delete" ON sermon_notes FOR DELETE USING (auth.uid() = author_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Sermon Study Prompts
CREATE TABLE IF NOT EXISTS sermon_study_prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sermon_id UUID NOT NULL,
  prompt TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE sermon_study_prompts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "sermon_study_prompts_select" ON sermon_study_prompts FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CRM / Donor Management
CREATE TABLE IF NOT EXISTS donor_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  total_given NUMERIC DEFAULT 0,
  last_gift_date TIMESTAMPTZ,
  first_gift_date TIMESTAMPTZ,
  gift_count INTEGER DEFAULT 0,
  is_recurring BOOLEAN DEFAULT false,
  category TEXT DEFAULT 'regular' CHECK (category IN ('major', 'recurring', 'regular', 'new', 'lapsed')),
  notes TEXT,
  segments JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, church_id)
);

ALTER TABLE donor_profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "donor_profiles_select" ON donor_profiles FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin', 'pastor')
      AND church_id = donor_profiles.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "donor_profiles_insert" ON donor_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "donor_profiles_update" ON donor_profiles FOR UPDATE USING (
    auth.uid() = user_id OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin', 'pastor')
      AND church_id = donor_profiles.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Donor segments
CREATE TABLE IF NOT EXISTS donor_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  criteria JSONB NOT NULL DEFAULT '{}',
  donor_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE donor_segments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "donor_segments_select" ON donor_segments FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "donor_segments_manage" ON donor_segments FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin')
      AND church_id = donor_segments.church_id
    )
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- RPC: Update signed_up_count on volunteer signups
CREATE OR REPLACE FUNCTION update_volunteer_signed_up_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE volunteer_slots
    SET signed_up_count = signed_up_count + 1
    WHERE id = NEW.slot_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE volunteer_slots
    SET signed_up_count = signed_up_count - 1
    WHERE id = OLD.slot_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "on_volunteer_signup_change" ON "volunteer_signups";
CREATE TRIGGER "on_volunteer_signup_change"
  AFTER INSERT OR UPDATE ON volunteer_signups
  FOR EACH ROW
  EXECUTE FUNCTION update_volunteer_signed_up_count();

-- RPC: Update donor profile on transaction
CREATE OR REPLACE FUNCTION update_donor_profile_on_giving()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.category = 'giving' AND NEW.status = 'completed' THEN
    INSERT INTO donor_profiles (user_id, church_id, total_given, last_gift_date, first_gift_date, gift_count)
    VALUES (
      NEW.user_id,
      COALESCE(NEW.church_id, (SELECT church_id FROM profiles WHERE id = NEW.user_id)),
      NEW.amount,
      NEW.created_at,
      NEW.created_at,
      1
    )
    ON CONFLICT (user_id, church_id) DO UPDATE SET
      total_given = donor_profiles.total_given + NEW.amount,
      last_gift_date = NEW.created_at,
      gift_count = donor_profiles.gift_count + 1,
      updated_at = now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "on_transaction_giving" ON "transactions";
CREATE TRIGGER "on_transaction_giving" 
  AFTER INSERT ON "transactions"
  FOR EACH ROW
  EXECUTE FUNCTION update_donor_profile_on_giving();
