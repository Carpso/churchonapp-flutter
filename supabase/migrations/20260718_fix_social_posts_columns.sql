-- Fix missing columns in social_posts table
-- Adds images, is_pinned, is_featured, featured_at columns

ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]';
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS featured_at TIMESTAMPTZ;

-- Fix overly permissive RLS UPDATE policy (any user could update any post)
DROP POLICY IF EXISTS "Authenticated users can update social posts" ON public.social_posts;
