-- Fix community group messaging: add community_group_members table and fix RLS
-- The community_groups table uses text group_identifier but messages.group_id expects UUID
-- Solution: Add a community_group_members table and update RLS to support community groups

-- 1. Community group members table
CREATE TABLE IF NOT EXISTS public.community_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.community_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member')),
  joined_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(group_id, user_id)
);

ALTER TABLE public.community_group_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view community group members" ON public.community_group_members;
CREATE POLICY "Users can view community group members"
  ON public.community_group_members FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can join community groups" ON public.community_group_members;
CREATE POLICY "Users can join community groups"
  ON public.community_group_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can leave community groups" ON public.community_group_members;
CREATE POLICY "Users can leave community groups"
  ON public.community_group_members FOR DELETE
  USING (user_id = auth.uid());

-- 2. Add tenant_id to messages for community group scoping
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS community_group_id UUID REFERENCES public.community_groups(id) ON DELETE SET NULL;

-- 3. Update RLS to allow reading messages in community groups
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
CREATE POLICY "Anyone can read messages"
  ON public.messages FOR SELECT
  USING (
    auth.uid() = user_id
    OR auth.uid() = receiver_id
    OR (
      group_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id::text = messages.group_id::text
        AND gm.user_id = auth.uid()
      )
    )
    OR (
      community_group_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.community_group_members cgm
        WHERE cgm.group_id = messages.community_group_id
        AND cgm.user_id = auth.uid()
      )
    )
  );

-- 4. Update INSERT policy for community group messages
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;
CREATE POLICY "Authenticated users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND (
      community_group_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.community_group_members cgm
        WHERE cgm.group_id = messages.community_group_id
        AND cgm.user_id = auth.uid()
      )
    )
  );

-- 5. Index for community group messages
CREATE INDEX IF NOT EXISTS idx_messages_community_group ON public.messages(community_group_id);
CREATE INDEX IF NOT EXISTS idx_community_group_members_group ON public.community_group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_community_group_members_user ON public.community_group_members(user_id);

-- 6. Auto-join church members to their church's general community group
CREATE OR REPLACE FUNCTION public.auto_join_community_group()
RETURNS TRIGGER AS $$
DECLARE
  v_group_id UUID;
BEGIN
  -- Find the general group for this user's church
  SELECT cg.id INTO v_group_id
  FROM public.community_groups cg
  WHERE cg.tenant_id = NEW.tenant_id
  AND cg.group_identifier = 'general'
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    INSERT INTO public.community_group_members (group_id, user_id)
    VALUES (v_group_id, NEW.id)
    ON CONFLICT (group_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: auto-join general group when profile is created
DROP TRIGGER IF EXISTS on_profile_created_auto_join ON public.profiles;
CREATE TRIGGER on_profile_created_auto_join
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  WHEN (NEW.tenant_id IS NOT NULL)
  EXECUTE FUNCTION public.auto_join_community_group();
