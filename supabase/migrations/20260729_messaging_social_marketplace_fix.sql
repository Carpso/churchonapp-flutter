DO $$
BEGIN
  CREATE POLICY messages_insert_auth ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = sender_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY messages_select_auth ON public.messages
    FOR SELECT TO authenticated
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR group_id IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY messages_update_auth ON public.messages
    FOR UPDATE TO authenticated
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY social_posts_insert_auth ON public.social_posts
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY social_posts_select_auth ON public.social_posts
    FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS conversation_id TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS group_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS media_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'text';
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sticker_id TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reply_to_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reply_to_text TEXT;

ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]';
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS media_url TEXT;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'text';

ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS express_delivery_fee NUMERIC DEFAULT 15;
