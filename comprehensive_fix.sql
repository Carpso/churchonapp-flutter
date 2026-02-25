-- COMPREHENSIVE FIX FOR KINGDOM APP BACKEND
-- Addresses: Events, Jobs, Business Meetings, Sermon Reactions, and Roles

-- 1. FIX ROLES & PROFILES
-- Ensure the public.profiles table has the 'role' column and it's used correctly
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'role') THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT DEFAULT 'member';
    END IF;
END $$;

-- 2. JOBS TABLE
CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    company TEXT,
    location TEXT,
    salary_range TEXT,
    type TEXT, -- Full-time, Part-time, Contract
    description TEXT,
    requirements TEXT[],
    church_id UUID, -- For tenant syncing
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. BUSINESS MEETING NOTES & VOTES
CREATE TABLE IF NOT EXISTS public.meeting_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id TEXT NOT NULL,
    author_id UUID REFERENCES auth.users(id),
    content TEXT NOT NULL,
    is_private BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.meeting_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id TEXT NOT NULL,
    voter_id UUID REFERENCES auth.users(id),
    option_selected TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(meeting_id, voter_id)
);

-- 4. SERMON REACTIONS
CREATE TABLE IF NOT EXISTS public.sermon_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sermon_id TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    reaction_type TEXT NOT NULL, -- 'amen', 'discuss', 'forward'
    content TEXT, -- For discuss/notes
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. UPDATE EVENTS FOR TENANT SYNC
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'events' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.events ADD COLUMN tenant_id UUID;
    END IF;
END $$;

-- 6. RLS POLICIES (Fixing "role" errors and ensuring access)
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sermon_reactions ENABLE ROW LEVEL SECURITY;

-- Jobs: Public Read
DROP POLICY IF EXISTS "Public Jobs Read" ON public.jobs;
CREATE POLICY "Public Jobs Read" ON public.jobs FOR SELECT USING (true);

-- Jobs: Admin Insert
DROP POLICY IF EXISTS "Admin Jobs Insert" ON public.jobs;
CREATE POLICY "Admin Jobs Insert" ON public.jobs FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'admin' OR role = 'superadmin'))
);

-- Meetings: Auth Read/Write
DROP POLICY IF EXISTS "Meeting Notes Access" ON public.meeting_notes;
CREATE POLICY "Meeting Notes Access" ON public.meeting_notes FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Meeting Votes Access" ON public.meeting_votes;
CREATE POLICY "Meeting Votes Access" ON public.meeting_votes FOR ALL USING (auth.uid() IS NOT NULL);

-- Sermon Reactions: Auth Access
DROP POLICY IF EXISTS "Sermon Reactions Access" ON public.sermon_reactions;
CREATE POLICY "Sermon Reactions Access" ON public.sermon_reactions FOR ALL USING (auth.uid() IS NOT NULL);

-- 7. MOCK DATA (Seeding)
-- Seeding Jobs
INSERT INTO public.jobs (title, company, location, salary_range, type, description, requirements)
VALUES 
('Media Director', 'Grace Assemblies', 'Lusaka', 'K15,000 - K20,000', 'Full-time', 'Lead our media and production team for Sunday services.', ARRAY['Experience in OBS', 'Video editing skills']),
('Children Ministry Coordinator', 'Zion Gates', 'Harare', 'K8,000 - K12,000', 'Part-time', 'Organizing curriculum and activities for Sunday school.', ARRAY['Teaching background', 'Love for children']);

-- Seeding Events (Global & Local)
INSERT INTO public.events (title, description, location, date, image_url, ticket_price, category)
VALUES 
('National Prayer Day', 'Join the entire nation in prayer.', 'National Stadium', now() + interval '10 days', 'https://images.unsplash.com/photo-1444464666168-49d633b867ad?w=800', 0, 'Spiritual'),
('Youth Impact Conference', 'Empowering the next generation.', 'Grace Cathedral', now() + interval '5 days', 'https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800', 50, 'Youth');

-- 8. REALTIME
ALTER PUBLICATION supabase_realtime ADD TABLE jobs, meeting_notes, meeting_votes, sermon_reactions;
