-- 1. Jobs notifications table
CREATE TABLE IF NOT EXISTS public.job_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('new_application', 'status_change', 'job_expiring')),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.job_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own job notifications" ON "public".job_notifications;
CREATE POLICY "Users can view own job notifications" ON "public".job_notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own job notifications" ON "public".job_notifications;
CREATE POLICY "Users can update own job notifications" ON "public".job_notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS idx_job_notifications_user ON public.job_notifications(user_id, is_read);

-- 2. Tenant ads / sponsored content table
CREATE TABLE IF NOT EXISTS public.tenant_ads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    target_url TEXT,
    ad_type TEXT NOT NULL DEFAULT 'banner' CHECK (ad_type IN ('banner', 'sponsored', 'promoted')),
    placement TEXT NOT NULL DEFAULT 'home' CHECK (placement IN ('home', 'events', 'marketplace', 'connect', 'all')),
    is_active BOOLEAN DEFAULT true,
    starts_at TIMESTAMPTZ DEFAULT now(),
    ends_at TIMESTAMPTZ,
    impressions INTEGER DEFAULT 0,
    max_impressions INTEGER,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.tenant_ads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view active ads" ON "public".tenant_ads;
CREATE POLICY "Anyone can view active ads" ON "public".tenant_ads FOR SELECT TO authenticated USING (is_active = true);
DROP POLICY IF EXISTS "Superadmins and employees can manage ads" ON "public".tenant_ads;
CREATE POLICY "Superadmins and employees can manage ads" ON "public".tenant_ads FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'superadmin' OR role = 'employee'))
);
CREATE INDEX IF NOT EXISTS idx_tenant_ads_active ON public.tenant_ads(tenant_id, is_active, placement);

-- 3. Emergency lockdown table
CREATE TABLE IF NOT EXISTS public.system_lockdown (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    is_locked BOOLEAN DEFAULT false,
    message TEXT DEFAULT 'System is under maintenance. Please check back later.',
    locked_by UUID REFERENCES auth.users(id),
    locked_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(is_locked)
);

INSERT INTO public.system_lockdown (is_locked) VALUES (false) ON CONFLICT DO NOTHING;

ALTER TABLE public.system_lockdown ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read lockdown status" ON "public".system_lockdown;
CREATE POLICY "Anyone can read lockdown status" ON "public".system_lockdown FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Superadmins can manage lockdown" ON "public".system_lockdown;
CREATE POLICY "Superadmins can manage lockdown" ON "public".system_lockdown FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'superadmin' OR role = 'employee'))
);

-- 4. Fasting mode app block schedules
CREATE TABLE IF NOT EXISTS public.fasting_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    fast_type TEXT DEFAULT 'prayer' CHECK (fast_type IN ('prayer', 'media', 'social', 'full')),
    blocked_apps TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.fasting_schedules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own fasting schedules" ON "public".fasting_schedules;
CREATE POLICY "Users can manage own fasting schedules" ON "public".fasting_schedules FOR ALL TO authenticated USING (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS idx_fasting_schedules_user ON public.fasting_schedules(user_id, is_active);

-- 5. Role onboarding status tracking
CREATE TABLE IF NOT EXISTS public.role_onboarding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    step INTEGER DEFAULT 1,
    total_steps INTEGER DEFAULT 3,
    is_completed BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, role)
);

ALTER TABLE public.role_onboarding ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own onboarding" ON "public".role_onboarding;
CREATE POLICY "Users can manage own onboarding" ON "public".role_onboarding FOR ALL TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Admins can view onboarding status" ON "public".role_onboarding;
CREATE POLICY "Admins can view onboarding status" ON "public".role_onboarding FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'superadmin' OR role = 'employee'))
);

-- 6. Add jobs notification columns
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS featured_until TIMESTAMPTZ;
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS application_deadline TIMESTAMPTZ;

-- 7. Add events hosting role columns
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS hosted_by UUID REFERENCES auth.users(id);
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS host_type TEXT DEFAULT 'church' CHECK (host_type IN ('church', 'admin', 'employee', 'promoter'));
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS is_paid_event BOOLEAN DEFAULT false;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_price DOUBLE PRECISION;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_limit INTEGER;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS tickets_sold INTEGER DEFAULT 0;

-- 8. Event passes table for games and paid events
CREATE TABLE IF NOT EXISTS public.event_passes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    quiz_event_id UUID REFERENCES public.quiz_events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    pass_type TEXT NOT NULL CHECK (pass_type IN ('event_ticket', 'quiz_pass', 'game_pass')),
    amount_paid DOUBLE PRECISION DEFAULT 0,
    payment_reference TEXT,
    is_used BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.event_passes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own passes" ON "public".event_passes;
CREATE POLICY "Users can view own passes" ON "public".event_passes FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Admins can view all passes" ON "public".event_passes;
CREATE POLICY "Admins can view all passes" ON "public".event_passes FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'superadmin' OR role = 'employee'))
);
DROP POLICY IF EXISTS "Users can insert own passes" ON "public".event_passes;
CREATE POLICY "Users can insert own passes" ON "public".event_passes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_event_passes_user ON public.event_passes(user_id);
CREATE INDEX IF NOT EXISTS idx_event_passes_event ON public.event_passes(event_id);

-- 9. Function to apply lockdown
CREATE OR REPLACE FUNCTION public.is_system_locked()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    locked BOOLEAN;
BEGIN
    SELECT is_locked INTO locked FROM public.system_lockdown LIMIT 1;
    RETURN COALESCE(locked, false);
END;
$$;

-- Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'tenant_ads') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE tenant_ads;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'job_notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE job_notifications;
  END IF;
END $$;
