-- Add platform_fee columns to track transaction cuts
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;

-- Ensure system treasury user exists in auth.users
INSERT INTO auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at,
  role,
  aud,
  raw_app_meta_data,
  raw_user_meta_data
)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'treasury@churchonapp.org',
  now(),
  now(),
  now(),
  'authenticated',
  'authenticated',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Kingdom Treasury"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

-- Ensure system treasury profile exists (using a stable UUID for system treasury)
INSERT INTO public.profiles (id, full_name, role, coins, created_at)
VALUES ('00000000-0000-0000-0000-000000000000', 'Kingdom Treasury', 'superadmin', 0, now())
ON CONFLICT (id) DO NOTHING;

-- Create service_reports table
CREATE TABLE IF NOT EXISTS public.service_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    attendance INTEGER DEFAULT 0,
    offering NUMERIC DEFAULT 0.0,
    testimony TEXT,
    reporter_id UUID REFERENCES auth.users(id),
    type TEXT DEFAULT 'service',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create pastor_reports table
CREATE TABLE IF NOT EXISTS public.pastor_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pastor_id UUID REFERENCES auth.users(id),
    organization_id TEXT NOT NULL,
    content TEXT,
    aggregated_stats JSONB DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS and public policies for reports
ALTER TABLE public.service_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pastor_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view service reports" ON public.service_reports;
DROP POLICY IF EXISTS "Pastors can submit service reports" ON public.service_reports;
CREATE POLICY "Anyone can view service reports" ON public.service_reports FOR SELECT USING (true);
CREATE POLICY "Pastors can submit service reports" ON public.service_reports FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can view pastor reports" ON public.pastor_reports;
DROP POLICY IF EXISTS "Pastors can submit pastor reports" ON public.pastor_reports;
CREATE POLICY "Anyone can view pastor reports" ON public.pastor_reports FOR SELECT USING (true);
CREATE POLICY "Pastors can submit pastor reports" ON public.pastor_reports FOR INSERT WITH CHECK (true);

-- Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'service_reports') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.service_reports;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'pastor_reports') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pastor_reports;
  END IF;
END $$;

