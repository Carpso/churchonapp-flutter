-- ═══════════════════════════════════════════════════════════════
-- Church On App - Final Deployment Migration
-- Run: supabase db query --linked --file supabase\migrations\20260826_final_deploy.sql
-- ═══════════════════════════════════════════════════════════════

-- ── Discipleship tables ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.discipleship_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  "order" INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.discipleship_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "discipleship_plans_select" ON public.discipleship_plans;
DROP POLICY IF EXISTS "discipleship_plans_insert" ON public.discipleship_plans;
DO $$ BEGIN CREATE POLICY "discipleship_plans_select" ON public.discipleship_plans FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "discipleship_plans_insert" ON public.discipleship_plans FOR INSERT WITH CHECK (auth.jwt() -> 'app_metadata' -> 'role' ? 'pastor' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'bishop' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Add is_pinned to user_notes ─────────────────────────────────
ALTER TABLE IF EXISTS public.user_notes ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- ── Game scores table ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.game_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  game_id TEXT NOT NULL,
  score INT NOT NULL DEFAULT 0,
  played_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_scores_game_id_score ON public.game_scores(game_id, score DESC);
CREATE INDEX IF NOT EXISTS idx_game_scores_user_game ON public.game_scores(user_id, game_id, score DESC);

ALTER TABLE public.game_scores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "game_scores_select" ON public.game_scores;
DROP POLICY IF EXISTS "game_scores_insert" ON public.game_scores;
DO $$ BEGIN CREATE POLICY "game_scores_select" ON public.game_scores FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "game_scores_insert" ON public.game_scores FOR INSERT WITH CHECK (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Kid's progress tracking ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.kids_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  points INT DEFAULT 0,
  weekly_activity_count INT DEFAULT 0,
  week_start DATE DEFAULT CURRENT_DATE,
  completed_resource_ids UUID[] DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kids_progress ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "kids_progress_select" ON public.kids_progress;
DROP POLICY IF EXISTS "kids_progress_insert" ON public.kids_progress;
DROP POLICY IF EXISTS "kids_progress_update" ON public.kids_progress;
DO $$ BEGIN CREATE POLICY "kids_progress_select" ON public.kids_progress FOR SELECT USING (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "kids_progress_insert" ON public.kids_progress FOR INSERT WITH CHECK (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "kids_progress_update" ON public.kids_progress FOR UPDATE USING (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Year planner extras ────────────────────────────────────────
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS reminder_minutes INT;
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS recurring_pattern TEXT;
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS recurring_end_date DATE;

-- ── Seed default emergency contacts ────────────────────────────
INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
SELECT 'Police', '911', 'shield', 'emergency_service', 1
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts WHERE name = 'Police');

INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
SELECT 'Ambulance', '992', 'ambulance', 'emergency_service', 2
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts WHERE name = 'Ambulance');

INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
SELECT 'Fire Brigade', '993', 'flame', 'emergency_service', 3
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts WHERE name = 'Fire Brigade');

INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
SELECT 'Victim Support Unit', '933', 'heart', 'emergency_service', 4
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts WHERE name = 'Victim Support Unit');

INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
SELECT 'Child Helpline', '116', 'baby', 'emergency_service', 5
WHERE NOT EXISTS (SELECT 1 FROM public.emergency_contacts WHERE name = 'Child Helpline');

-- ── Seed default discipleship plans ────────────────────────────
INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Water Baptism', 'Understanding and receiving water baptism', 1
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Water Baptism');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Bible Reading Plan', 'Daily Bible reading habit', 2
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Bible Reading Plan');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Prayer Foundation', 'Building a prayer life', 3
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Prayer Foundation');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Church Membership', 'Understanding church membership', 4
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Church Membership');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Spiritual Gifts', 'Discover your spiritual gifts', 5
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Spiritual Gifts');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Worship Lifestyle', 'Living a life of worship', 6
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Worship Lifestyle');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Evangelism Training', 'Sharing your faith', 7
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Evangelism Training');

INSERT INTO public.discipleship_plans (title, description, "order")
SELECT 'Leadership Development', 'Growing as a leader', 8
WHERE NOT EXISTS (SELECT 1 FROM public.discipleship_plans WHERE title = 'Leadership Development');

-- ── Notification channels table ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_channels (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT DEFAULT 'bell',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.notification_channels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification_channels_select" ON public.notification_channels;
DO $$ BEGIN CREATE POLICY "notification_channels_select" ON public.notification_channels FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO public.notification_channels (id, name, description, icon, sort_order) VALUES
  ('coa_announcements', 'Announcements', 'Church-wide announcements and alerts', 'megaphone', 1),
  ('coa_chat', 'Chat Messages', 'Direct messages and group chats', 'message-circle', 2),
  ('coa_posts', 'Social Posts', 'New posts from church community', 'users', 3),
  ('coa_payments', 'Payments', 'Payment confirmations and receipts', 'wallet', 4),
  ('coa_events', 'Events', 'Event reminders and updates', 'calendar', 5),
  ('coa_prayers', 'Prayers', 'Prayer request notifications', 'heart', 6),
  ('coa_testimonies', 'Testimonies', 'New testimonies shared', 'star', 7),
  ('coa_klips', 'Kingdom Klips', 'New video clip uploads', 'video', 8),
  ('coa_fasting', 'Fasting', 'Fasting reminders and updates', 'clock', 9)
ON CONFLICT (id) DO NOTHING;

-- ── Notification preferences RLS ───────────────────────────────
ALTER TABLE IF EXISTS public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification_preferences_select" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_insert" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_update" ON public.notification_preferences;
DO $$ BEGIN CREATE POLICY "notification_preferences_select" ON public.notification_preferences FOR SELECT USING (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "notification_preferences_insert" ON public.notification_preferences FOR INSERT WITH CHECK (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "notification_preferences_update" ON public.notification_preferences FOR UPDATE USING (auth.uid() = user_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Baptism push columns ───────────────────────────────────────
ALTER TABLE IF EXISTS public.baptisms ADD COLUMN IF NOT EXISTS notify_on_schedule BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS public.baptisms ADD COLUMN IF NOT EXISTS notify_on_complete BOOLEAN DEFAULT true;

-- ── Performance indexes ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user ON public.notification_preferences(user_id, channel_id);

-- ── Bible study sessions table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bible_study_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  study_date DATE NOT NULL,
  study_time TIME,
  leader TEXT,
  location TEXT,
  materials_url TEXT,
  max_attendees INT DEFAULT 50,
  status TEXT DEFAULT 'scheduled',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bible_study_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bible_study_sessions_select" ON public.bible_study_sessions;
DROP POLICY IF EXISTS "bible_study_sessions_insert" ON public.bible_study_sessions;
DROP POLICY IF EXISTS "bible_study_sessions_update" ON public.bible_study_sessions;
DROP POLICY IF EXISTS "bible_study_sessions_delete" ON public.bible_study_sessions;
DO $$ BEGIN CREATE POLICY "bible_study_sessions_select" ON public.bible_study_sessions FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "bible_study_sessions_insert" ON public.bible_study_sessions FOR INSERT WITH CHECK (auth.role() = 'authenticated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "bible_study_sessions_update" ON public.bible_study_sessions FOR UPDATE USING (auth.role() = 'authenticated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "bible_study_sessions_delete" ON public.bible_study_sessions FOR DELETE USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'pastor' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'bishop' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
