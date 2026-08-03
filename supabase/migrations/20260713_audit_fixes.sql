-- 1. Sync auth.users to public.profiles Automatically
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, coins, is_work_mode, avatar_url, tenant_id)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Believer'),
    CASE WHEN new.email = 'superadmingosomzkay7@churchonapp.com' THEN 'superadmin' ELSE 'member' END,
    500,
    false,
    COALESCE(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    NULL
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 2. Restrict messages access to participants (RLS Policy Update)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
CREATE POLICY "Anyone can read messages" ON public.messages
    FOR SELECT TO authenticated
    USING (
        auth.uid() = sender_id OR
        auth.uid() = receiver_id OR
        (group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id::text = messages.group_id AND gm.user_id = auth.uid()
        ))
    );


-- 3. Social posts likes and comments counters triggers
-- A. Likes counter
CREATE OR REPLACE FUNCTION public.sync_social_likes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.social_posts
    SET likes_count = COALESCE(likes_count, 0) + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.social_posts
    SET likes_count = GREATEST(0, COALESCE(likes_count, 0) - 1)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_social_likes ON public.social_likes;
CREATE TRIGGER trg_sync_social_likes
  AFTER INSERT OR DELETE ON public.social_likes
  FOR EACH ROW EXECUTE FUNCTION public.sync_social_likes_count();

-- B. Comments counter
CREATE OR REPLACE FUNCTION public.sync_social_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.social_posts
    SET comments_count = COALESCE(comments_count, 0) + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.social_posts
    SET comments_count = GREATEST(0, COALESCE(comments_count, 0) - 1)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_social_comments ON public.social_comments;
CREATE TRIGGER trg_sync_social_comments
  AFTER INSERT OR DELETE ON public.social_comments
  FOR EACH ROW EXECUTE FUNCTION public.sync_social_comments_count();
