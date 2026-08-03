-- Final enhancements migration for Church On App

-- 1. Add notification_channels table for user preferences
CREATE TABLE IF NOT EXISTS public.notification_channels (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT DEFAULT 'bell',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

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

ALTER TABLE public.notification_channels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification_channels_select" ON public.notification_channels;
CREATE POLICY "notification_channels_select" ON public.notification_channels FOR SELECT USING (true);

-- 2. Add notification_preferences RLS (already exists, but ensure policies)
ALTER TABLE IF EXISTS public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification_preferences_select" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_insert" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_update" ON public.notification_preferences;
CREATE POLICY "notification_preferences_select" ON public.notification_preferences FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notification_preferences_insert" ON public.notification_preferences FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "notification_preferences_update" ON public.notification_preferences FOR UPDATE USING (auth.uid() = user_id);

-- 3. Add baptism push columns
ALTER TABLE IF EXISTS public.baptisms ADD COLUMN IF NOT EXISTS notify_on_schedule BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS public.baptisms ADD COLUMN IF NOT EXISTS notify_on_complete BOOLEAN DEFAULT true;

-- 4. Add kids_progress.weekly_activity_count default
ALTER TABLE IF EXISTS public.kids_progress ALTER COLUMN weekly_activity_count SET DEFAULT 0;

-- 5. Create index for faster notification queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user ON public.notification_preferences(user_id, channel_id);

-- 6. Ensure all game features have game_scores index
CREATE INDEX IF NOT EXISTS idx_game_scores_user ON public.game_scores(user_id, game_id, score DESC);

-- 7. Add RLS for game_scores
DROP POLICY IF EXISTS "game_scores_select" ON public.game_scores;
DROP POLICY IF EXISTS "game_scores_insert" ON public.game_scores;
CREATE POLICY "game_scores_select" ON public.game_scores FOR SELECT USING (true);
CREATE POLICY "game_scores_insert" ON public.game_scores FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 8. Add bible_study_sessions table (created by the feature, ensure it exists)
CREATE TABLE IF NOT EXISTS public.bible_study_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
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
CREATE POLICY "bible_study_sessions_select" ON public.bible_study_sessions FOR SELECT USING (true);
CREATE POLICY "bible_study_sessions_insert" ON public.bible_study_sessions FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "bible_study_sessions_update" ON public.bible_study_sessions FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "bible_study_sessions_delete" ON public.bible_study_sessions FOR DELETE USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'pastor' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'bishop' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin');
