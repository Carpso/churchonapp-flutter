-- Carpso Ride fixes: ride_preferences table + approved_by column

-- 1. Create ride_preferences table for per-user ride preferences
CREATE TABLE IF NOT EXISTS public.ride_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    gospel_music BOOLEAN DEFAULT true,
    quiet_ride BOOLEAN DEFAULT false,
    ac_on BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ride_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own ride preferences" ON public.ride_preferences;
DO $$ BEGIN CREATE POLICY "Users can view own ride preferences" ON public.ride_preferences
    FOR SELECT TO authenticated USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DROP POLICY IF EXISTS "Users can upsert own ride preferences" ON public.ride_preferences;
DO $$ BEGIN CREATE POLICY "Users can upsert own ride preferences" ON public.ride_preferences
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DROP POLICY IF EXISTS "Users can update own ride preferences" ON public.ride_preferences;
DO $$ BEGIN CREATE POLICY "Users can update own ride preferences" ON public.ride_preferences
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Add approved_by column to ride_registrations for superadmin/COA approval
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ride_registrations') THEN
        EXECUTE 'ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id)';
    END IF;
END $$;

-- 3. Add preferences JSONB column to ride_requests
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ride_requests') THEN
        EXECUTE 'ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS preferences JSONB DEFAULT NULL';
    END IF;
END $$;

-- 4. Enable realtime for ride_preferences
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'ride_preferences') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE ride_preferences;
    END IF;
END $$;
