CREATE TABLE IF NOT EXISTS public.social_posts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    content text,
    media_url text,
    media_type text,
    likes_count integer DEFAULT 0,
    comments_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    is_moderated boolean DEFAULT false,
    prophetic_weight double precision DEFAULT 0.0,
    category text DEFAULT 'general'
);

CREATE TABLE IF NOT EXISTS public.social_likes (
    post_id uuid REFERENCES public.social_posts(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.social_comments (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    post_id uuid REFERENCES public.social_posts(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    content text,
    created_at timestamp with time zone DEFAULT now()
);

-- RLS
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public Read Posts" ON public.social_posts FOR SELECT USING (true);
CREATE POLICY "Auth Insert Posts" ON public.social_posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Public Read Likes" ON public.social_likes FOR SELECT USING (true);
CREATE POLICY "Auth Insert Likes" ON public.social_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Public Read Comments" ON public.social_comments FOR SELECT USING (true);
CREATE POLICY "Auth Insert Comments" ON public.social_comments FOR INSERT WITH CHECK (auth.uid() = user_id);
