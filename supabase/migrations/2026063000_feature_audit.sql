-- 1. Alter testimonies table to add missing fields for full functionality
ALTER TABLE public.testimonies ADD COLUMN IF NOT EXISTS user_photo TEXT;
ALTER TABLE public.testimonies ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.testimonies ADD COLUMN IF NOT EXISTS praise_count INTEGER DEFAULT 0;
ALTER TABLE public.testimonies ADD COLUMN IF NOT EXISTS praised_by UUID[] DEFAULT '{}';

-- Enable RLS policies on testimonies
ALTER TABLE public.testimonies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view testimonies" ON public.testimonies;
CREATE POLICY "Anyone can view testimonies" ON public.testimonies FOR SELECT USING (true);

DROP POLICY IF EXISTS "Authenticated users can submit testimonies" ON public.testimonies;
CREATE POLICY "Authenticated users can submit testimonies" ON public.testimonies FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authenticated users can update testimonies" ON public.testimonies;
CREATE POLICY "Authenticated users can update testimonies" ON public.testimonies FOR UPDATE USING (true);

-- 2. Create daily_bible_verses table
CREATE TABLE IF NOT EXISTS public.daily_bible_verses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reference TEXT NOT NULL,
    text TEXT NOT NULL,
    posted_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS policies on daily_bible_verses
ALTER TABLE public.daily_bible_verses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view daily bible verses" ON public.daily_bible_verses;
CREATE POLICY "Anyone can view daily bible verses" ON public.daily_bible_verses FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can post daily bible verses" ON public.daily_bible_verses;
CREATE POLICY "Admins can post daily bible verses" ON public.daily_bible_verses FOR INSERT WITH CHECK (auth.uid() = posted_by);

-- Enable updates to prayers so users can pray for request (increment prayer count)
DROP POLICY IF EXISTS "Authenticated users can update prayers" ON public.prayers;
CREATE POLICY "Authenticated users can update prayers" ON public.prayers FOR UPDATE USING (true);

-- Enable updates to social posts so users can like/comment
DROP POLICY IF EXISTS "Authenticated users can update social posts" ON public.social_posts;
CREATE POLICY "Authenticated users can update social posts" ON public.social_posts FOR UPDATE USING (true);

-- Enable Realtime for daily_bible_verses safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'daily_bible_verses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE daily_bible_verses;
  END IF;
END $$;

-- Add subscription fields to churches table
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS payment_reference TEXT;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS payment_submitted_at TIMESTAMPTZ;

-- 3. Create platform_settings table
CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS policies on platform_settings
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view platform settings" ON public.platform_settings;
CREATE POLICY "Anyone can view platform settings" ON public.platform_settings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can update platform settings" ON public.platform_settings;
CREATE POLICY "Admins can update platform settings" ON public.platform_settings FOR ALL USING (true);

-- Seed initial rates
INSERT INTO public.platform_settings (key, value) VALUES
('silver_subscription_fee', '50'),
('gold_subscription_fee', '150'),
('church_subscription_fee', '1500')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
-- Create radio_stations table
CREATE TABLE IF NOT EXISTS public.radio_stations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    stream_url TEXT NOT NULL,
    location TEXT NOT NULL,
    is_private BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS policies on radio_stations
ALTER TABLE public.radio_stations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view radio stations" ON public.radio_stations;
CREATE POLICY "Anyone can view radio stations" ON public.radio_stations FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage radio stations" ON public.radio_stations;
CREATE POLICY "Admins can manage radio stations" ON public.radio_stations FOR ALL USING (true);

-- Seed initial stations
INSERT INTO public.radio_stations (name, stream_url, location, is_private) VALUES
('Radio Christian Voice', 'http://stream.rcv.co.zm:8000/stream', 'Lusaka', false),
('United Voice Radio', 'https://streaming.unitedvoice.radio/stream', 'Lusaka', false),
('Radio Maria Zambia', 'http://net.radiomaria.org.ar:8000/Zamba', 'National', false),
('Radio Icengelo', 'http://45.89.84.148:8000/radio.mp3', 'Copperbelt', false),
('Yatsani Radio', 'http://yatsaniradio.stream:80/live', 'Lusaka', false),
('K-LOVE Radio', 'http://klove.live.wostreaming.net/web-mp3', 'USA', false),
('Air1 Worship', 'http://air1.live.wostreaming.net/web-mp3', 'USA', false),
('Premier Christian', 'https://premier.live.wostreaming.net/web-mp3', 'UK', false),
('Private Test Station', 'https://private-stream.com', 'Private', true)
ON CONFLICT (name) DO UPDATE SET
    stream_url = EXCLUDED.stream_url,
    location = EXCLUDED.location,
    is_private = EXCLUDED.is_private;

-- 4. Add streak columns to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS streak_count INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;

-- 5. Fix social relationships to profiles table instead of auth.users
ALTER TABLE public.social_posts DROP CONSTRAINT IF EXISTS social_posts_user_id_fkey;
ALTER TABLE public.social_posts ADD CONSTRAINT social_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.social_comments DROP CONSTRAINT IF EXISTS social_comments_user_id_fkey;
ALTER TABLE public.social_comments ADD CONSTRAINT social_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.social_likes DROP CONSTRAINT IF EXISTS social_likes_user_id_fkey;
ALTER TABLE public.social_likes ADD CONSTRAINT social_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
