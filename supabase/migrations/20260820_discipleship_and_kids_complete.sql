-- Discipleship tables
CREATE TABLE IF NOT EXISTS public.discipleship_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  "order" INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.discipleship_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "discipleship_plans_select" ON public.discipleship_plans
  FOR SELECT USING (true);

CREATE POLICY "discipleship_plans_insert" ON public.discipleship_plans
  FOR INSERT WITH CHECK (auth.jwt() -> 'app_metadata' -> 'role' ? 'pastor' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'bishop' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin');

-- Add is_pinned to user_notes
ALTER TABLE IF EXISTS public.user_notes ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Game scores table
CREATE TABLE IF NOT EXISTS public.game_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  game_id TEXT NOT NULL,
  score INT NOT NULL DEFAULT 0,
  played_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_scores_game_score ON public.game_scores(game_id, score DESC);

ALTER TABLE public.game_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_scores_select" ON public.game_scores
  FOR SELECT USING (true);

CREATE POLICY "game_scores_insert" ON public.game_scores
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Emergency contacts table (tenant-configurable)
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  icon TEXT DEFAULT 'phone',
  category TEXT DEFAULT 'emergency_service',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "emergency_contacts_select" ON public.emergency_contacts
  FOR SELECT USING (true);

CREATE POLICY "emergency_contacts_insert" ON public.emergency_contacts
  FOR INSERT WITH CHECK (auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'admin');

CREATE POLICY "emergency_contacts_update" ON public.emergency_contacts
  FOR UPDATE USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'admin');

CREATE POLICY "emergency_contacts_delete" ON public.emergency_contacts
  FOR DELETE USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin' OR auth.jwt() -> 'app_metadata' -> 'role' ? 'admin');

-- Kid's points/progress tracking
CREATE TABLE IF NOT EXISTS public.kids_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  points INT DEFAULT 0,
  weekly_activity_count INT DEFAULT 0,
  week_start DATE DEFAULT CURRENT_DATE,
  completed_resource_ids UUID[] DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kids_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "kids_progress_select" ON public.kids_progress
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "kids_progress_insert" ON public.kids_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "kids_progress_update" ON public.kids_progress
  FOR UPDATE USING (auth.uid() = user_id);

-- Add reminder_minutes and recurring_pattern to year_planner
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS reminder_minutes INT;
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS recurring_pattern TEXT;
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS recurring_end_date DATE;
