-- ═══════════════════════════════════════════════════════════════
-- RUN THIS IN: https://supabase.com/dashboard/project/daboihiudmglwhdfvsku/sql/new
-- Paste everything below and click "Run"
-- ═══════════════════════════════════════════════════════════════

-- ── PART 1: Fix social_posts missing columns ──────────────────
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]';
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS featured_at TIMESTAMPTZ;

DROP POLICY IF EXISTS "Authenticated users can update social posts" ON public.social_posts;

-- ── PART 2: Fix community group messaging ─────────────────────

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

-- 2. Add community_group_id to messages
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

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_messages_community_group ON public.messages(community_group_id);
CREATE INDEX IF NOT EXISTS idx_community_group_members_group ON public.community_group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_community_group_members_user ON public.community_group_members(user_id);

-- 6. Auto-join church members to their church's general community group
CREATE OR REPLACE FUNCTION public.auto_join_community_group()
RETURNS TRIGGER AS $$
DECLARE
  v_group_id UUID;
BEGIN
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

DROP TRIGGER IF EXISTS on_profile_created_auto_join ON public.profiles;
CREATE TRIGGER on_profile_created_auto_join
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  WHEN (NEW.tenant_id IS NOT NULL)
  EXECUTE FUNCTION public.auto_join_community_group();


-- ── PART 3: Fix Profiles RLS Recursion (42P17) ─────────────────
CREATE OR REPLACE FUNCTION public.is_admin_or_employee()
RETURNS BOOLEAN
SET search_path = public, auth
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _role TEXT;
BEGIN
  -- Try checking from JWT claims first (very fast)
  _role := (auth.jwt() -> 'app_metadata' ->> 'role');
  IF _role IN ('superadmin', 'employee') THEN
    RETURN TRUE;
  END IF;

  -- Fallback: query auth.users directly (bypasses profiles table RLS)
  SELECT (raw_app_meta_data ->> 'role') INTO _role
  FROM auth.users
  WHERE id = auth.uid();

  RETURN COALESCE(_role, 'member') IN ('superadmin', 'employee');
END;
$$;

DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;

CREATE POLICY "Superadmins and employees can manage all profiles" ON public.profiles
  FOR ALL TO authenticated
  USING (public.is_admin_or_employee())
  WITH CHECK (public.is_admin_or_employee());

