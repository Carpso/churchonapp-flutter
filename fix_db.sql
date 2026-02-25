-- Add missing columns to public.churches
ALTER TABLE public.churches 
ADD COLUMN IF NOT EXISTS slug TEXT,
ADD COLUMN IF NOT EXISTS contact_phone TEXT,
ADD COLUMN IF NOT EXISTS pastor_name TEXT,
ADD COLUMN IF NOT EXISTS treasurer_phone TEXT,
ADD COLUMN IF NOT EXISTS logo_url TEXT,
ADD COLUMN IF NOT EXISTS directions TEXT,
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS settings JSONB;

-- Ensure role exists in public.profiles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role') THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT DEFAULT 'member';
    END IF;
END $$;

-- Check if profile_role enum exists, if not create it or just use text
-- The error "22023 role does not exist" often means it's trying to cast to a type.
-- Let's check if there's a trigger or something that uses 'role' as a type.
