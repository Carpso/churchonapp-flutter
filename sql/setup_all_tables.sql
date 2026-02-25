-- SQL Setup for Church On App Features
-- Run these in your Supabase SQL Editor

-- 1. Profiles (Ensure all columns exist)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role TEXT DEFAULT 'member',
    coins INT DEFAULT 0,
    is_work_mode BOOLEAN DEFAULT false,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    balance_cc DOUBLE PRECISION DEFAULT 0.0,
    balance_zmw DOUBLE PRECISION DEFAULT 0.0,
    phone_number TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Churches (Tenants)
CREATE TABLE IF NOT EXISTS public.churches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    logo_url TEXT,
    primary_color TEXT DEFAULT '#FFD700',
    accent_color TEXT DEFAULT '#1A1A1A',
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    settings JSONB DEFAULT '{}',
    treasurer_phone TEXT,
    pastor_name TEXT,
    contact_phone TEXT,
    address TEXT,
    country TEXT DEFAULT 'Zambia',
    directions TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Prayers
CREATE TABLE IF NOT EXISTS public.prayers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    user_name TEXT,
    user_photo TEXT,
    content TEXT,
    category TEXT,
    visibility TEXT DEFAULT 'public',
    prayer_count INT DEFAULT 0,
    prayed_by UUID[] DEFAULT '{}',
    is_anonymous BOOLEAN DEFAULT false,
    ai_encouragement TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Kingdom News
CREATE TABLE IF NOT EXISTS public.kingdom_news (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    excerpt TEXT,
    content TEXT,
    image_url TEXT,
    author_id UUID REFERENCES auth.users(id),
    author_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Sermons
CREATE TABLE IF NOT EXISTS public.sermons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES public.churches(id),
    title TEXT NOT NULL,
    preacher TEXT,
    video_url TEXT,
    thumbnail_url TEXT,
    category TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 6. Church Live Status
CREATE TABLE IF NOT EXISTS public.church_live_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID UNIQUE REFERENCES public.churches(id),
    is_live BOOLEAN DEFAULT false,
    stream_url TEXT,
    title TEXT,
    viewer_count INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 7. Jobs
CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES public.churches(id),
    employer_id UUID,
    title TEXT NOT NULL,
    company TEXT,
    location TEXT,
    salary_range TEXT,
    type TEXT,
    description TEXT,
    requirements TEXT[],
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. Kingdom Klips
CREATE TABLE IF NOT EXISTS public.klips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    user_name TEXT,
    description TEXT,
    video_url TEXT,
    thumbnail_url TEXT,
    likes INT DEFAULT 0,
    liked_by UUID[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 9. Events
CREATE TABLE IF NOT EXISTS public.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    date TIMESTAMPTZ NOT NULL,
    image_url TEXT,
    ticket_price DOUBLE PRECISION DEFAULT 0.0,
    attendee_count INT DEFAULT 0,
    category TEXT DEFAULT 'General',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 10. Event Registrations
CREATE TABLE IF NOT EXISTS public.event_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(event_id, user_id)
);

-- 11. Social Posts
CREATE TABLE IF NOT EXISTS public.social_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT,
    media_url TEXT,
    media_type TEXT,
    likes_count INT DEFAULT 0,
    comments_count INT DEFAULT 0,
    is_moderated BOOLEAN DEFAULT false,
    prophetic_weight DOUBLE PRECISION DEFAULT 0.0,
    category TEXT DEFAULT 'general',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 12. Social Likes
CREATE TABLE IF NOT EXISTS public.social_likes (
    post_id UUID REFERENCES public.social_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY(post_id, user_id)
);

-- 13. Testimonies
CREATE TABLE IF NOT EXISTS public.testimonies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT,
    content TEXT NOT NULL,
    category TEXT,
    likes INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS (Row Level Security) - Basics
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kingdom_news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sermons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_live_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.klips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.testimonies ENABLE ROW LEVEL SECURITY;

-- Select Policies (Public Read)
CREATE POLICY "Allow public read on churches" ON public.churches FOR SELECT USING (true);
CREATE POLICY "Allow public read on prayers" ON public.prayers FOR SELECT USING (true);
CREATE POLICY "Allow public read on kingdom_news" ON public.kingdom_news FOR SELECT USING (true);
CREATE POLICY "Allow public read on sermons" ON public.sermons FOR SELECT USING (true);
CREATE POLICY "Allow public read on church_live_status" ON public.church_live_status FOR SELECT USING (true);
CREATE POLICY "Allow public read on jobs" ON public.jobs FOR SELECT USING (true);
CREATE POLICY "Allow public read on klips" ON public.klips FOR SELECT USING (true);
CREATE POLICY "Allow public read on events" ON public.events FOR SELECT USING (true);
CREATE POLICY "Allow public read on social_posts" ON public.social_posts FOR SELECT USING (true);
CREATE POLICY "Allow public read on testimonies" ON public.testimonies FOR SELECT USING (true);

-- My registrations policy
CREATE POLICY "Users can see their own registrations" ON public.event_registrations FOR SELECT USING (auth.uid() = user_id);

-- Insert Policies
CREATE POLICY "Users can create their own prayers" ON public.prayers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can create their own posts" ON public.social_posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can register for events" ON public.event_registrations FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Anyone can register a church" ON public.churches FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can create their profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Allow public select on profiles" ON public.profiles FOR SELECT USING (true);

-- Enable Realtime for streaming features
ALTER PUBLICATION supabase_realtime ADD TABLE prayers, kingdom_news, church_live_status, klips, jobs, events, social_posts, testimonies;

-- 14. Expansion Leads (Tracking for expansion)
CREATE TABLE IF NOT EXISTS public.expansion_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    church_name TEXT,
    location TEXT,
    interest_type TEXT, -- e.g., 'notify_on_registration', 'general_inquiry'
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.expansion_leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can create their own leads" ON public.expansion_leads FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins can read all leads" ON public.expansion_leads FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
        AND profiles.role IN ('superadmin', 'employee')
    )
);

ALTER PUBLICATION supabase_realtime ADD TABLE expansion_leads;
