-- MASTER DEPLOYMENT SCRIPT FOR CHURCH ON APP
-- This script consolidates all necessary backend changes for:
-- 1. Profiles & Roles
-- 2. Business Meetings (Notes & Votes)
-- 3. Sermon Engagement (Reactions & Insights)
-- 4. Jobs Portal
-- 5. Event Syncing
-- 6. Infrastructure Permissions & Geo-sync

-- 1. PROFILES & INFRASTRUCTURE
-- Ensure the public.profiles table has all necessary columns
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'role') THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT DEFAULT 'member';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'is_work_mode') THEN
        ALTER TABLE public.profiles ADD COLUMN is_work_mode BOOLEAN DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'lat') THEN
        ALTER TABLE public.profiles ADD COLUMN lat DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'lng') THEN
        ALTER TABLE public.profiles ADD COLUMN lng DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'coins') THEN
        ALTER TABLE public.profiles ADD COLUMN coins INTEGER DEFAULT 500;
    END IF;
END $$;

-- 2. JOBS TABLE
CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    company TEXT,
    location TEXT,
    salary TEXT,
    type TEXT, -- Full-time, Part-time, Contract
    description TEXT,
    contact TEXT,
    employer_id UUID,
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
    meeting_id TEXT NOT NULL,
    voter_id UUID REFERENCES auth.users(id),
    option_selected TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (meeting_id, voter_id)
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

-- 5. UPDATE EVENTS FOR TENANT SYNC & SCHEMA CONSISTENCY
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.events ADD COLUMN tenant_id UUID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'description') THEN
        ALTER TABLE public.events ADD COLUMN description TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'location') THEN
        ALTER TABLE public.events ADD COLUMN location TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'category') THEN
        ALTER TABLE public.events ADD COLUMN category TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'ticket_price') THEN
        ALTER TABLE public.events ADD COLUMN ticket_price DOUBLE PRECISION DEFAULT 0.0;
    END IF;
END $$;

-- 6. RLS POLICIES
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sermon_reactions ENABLE ROW LEVEL SECURITY;

-- Jobs Policy
DROP POLICY IF EXISTS "Public Jobs Read" ON public.jobs;
CREATE POLICY "Public Jobs Read" ON public.jobs FOR SELECT USING (true);
DROP POLICY IF EXISTS "Auth Post Jobs" ON public.jobs;
CREATE POLICY "Auth Post Jobs" ON public.jobs FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Meeting Policy
DROP POLICY IF EXISTS "Meeting Records Access" ON public.meeting_notes;
CREATE POLICY "Meeting Records Access" ON public.meeting_notes FOR ALL USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Meeting Votes Access" ON public.meeting_votes;
CREATE POLICY "Meeting Votes Access" ON public.meeting_votes FOR ALL USING (auth.uid() IS NOT NULL);

-- Sermon Policy
DROP POLICY IF EXISTS "Sermon Insights Access" ON public.sermon_reactions;
CREATE POLICY "Sermon Insights Access" ON public.sermon_reactions FOR ALL USING (auth.uid() IS NOT NULL);

-- 7. REALTIME
-- Try to add tables to publication safely
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE jobs;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE meeting_notes;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE meeting_votes;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE sermon_reactions;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 8. SEED DATA
-- Insert initial jobs if none exist
INSERT INTO public.jobs (title, company, location, salary, type, description, contact)
SELECT 'Media Director', 'Grace Assemblies', 'Lusaka', 'K15,000', 'Full-time', 'Production lead for Sunday services.', 'media@grace.org'
WHERE NOT EXISTS (SELECT 1 FROM public.jobs WHERE title = 'Media Director');

-- Refresh Events if empty (Using corrected mapping for public.events)
INSERT INTO public.events (title, description, location, event_date, ticket_price, category)
SELECT 'National Prayer Day', 'Strategic intercession for the nation.', 'National Stadium', now() + interval '10 days', 0.0, 'Spiritual'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'National Prayer Day');
