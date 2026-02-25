-- Unified SQL Fix for Social, Klips, Marketplace, and Events
-- This script ensures all tables exist and have the correct RLS policies for Posting and Viewing.

-- 1. Kingdom Klips (Unifying videos table)
CREATE TABLE IF NOT EXISTS public.klips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    title TEXT,
    description TEXT,
    video_url TEXT NOT NULL,
    thumbnail_url TEXT,
    views INT DEFAULT 0,
    likes INT DEFAULT 0,
    speaker TEXT,
    church_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Marketplace Items
CREATE TABLE IF NOT EXISTS public.marketplace_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    category TEXT,
    image TEXT,
    description TEXT,
    vendor_name TEXT,
    vendor_id UUID REFERENCES auth.users(id),
    condition TEXT,
    market_type TEXT DEFAULT 'general',
    status TEXT DEFAULT 'active',
    is_curated BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Social Posts (Ensure it matches the service)
-- (Already exists but let's ensure social_likes and social_comments are fully functional)
CREATE TABLE IF NOT EXISTS public.social_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES public.social_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Enable RLS on everything
ALTER TABLE public.klips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;

-- 5. Select Policies (Public Read)
DROP POLICY IF EXISTS "Public Read Klips" ON public.klips;
CREATE POLICY "Public Read Klips" ON public.klips FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public Read Marketplace" ON public.marketplace_items;
CREATE POLICY "Public Read Marketplace" ON public.marketplace_items FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public Read Events" ON public.events;
CREATE POLICY "Public Read Events" ON public.events FOR SELECT USING (true);

-- 6. Insert Policies (Auth Required)
DROP POLICY IF EXISTS "Auth Insert Klips" ON public.klips;
CREATE POLICY "Auth Insert Klips" ON public.klips FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Auth Insert Marketplace" ON public.marketplace_items;
CREATE POLICY "Auth Insert Marketplace" ON public.marketplace_items FOR INSERT WITH CHECK (auth.uid() = vendor_id);

DROP POLICY IF EXISTS "Auth Insert Events" ON public.events;
CREATE POLICY "Auth Insert Events" ON public.events FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Auth Insert Social" ON public.social_posts;
CREATE POLICY "Auth Insert Social" ON public.social_posts FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 7. Realtime Enablement
ALTER PUBLICATION supabase_realtime ADD TABLE klips, marketplace_items, social_posts, events;
