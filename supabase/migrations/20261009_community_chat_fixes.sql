-- 20261009 — Community group chat + privacy + member-count fixes
--
-- 1. CRITICAL: messages_select_auth dropped the community_group_id membership
--    branch (20260833) — other members could never READ community group chat.
--    Restore it so group messages are visible to every member of the group.
-- 2. HIGH: community_group_members SELECT was USING(true) — any authenticated
--    user could enumerate members of EVERY church's private groups. Scope it.
-- 3. HIGH: member_count never updated on join/leave. Add trigger-based sync so
--    the count is accurate regardless of which client path joins/leaves.

-- ──────────────────────────────────────────────────────────────
-- 1. Fix messages SELECT RLS (community group member visibility)
-- ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
DROP POLICY IF EXISTS "messages_select_auth" ON public.messages;
CREATE POLICY "messages_select_auth"
  ON public.messages FOR SELECT
  TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR auth.uid() = user_id
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

-- Ensure a valid INSERT policy also exists for community-group messages so the
-- sender can post into groups they belong to.
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_auth" ON public.messages;
CREATE POLICY "messages_insert_auth"
  ON public.messages FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    OR auth.uid() = user_id
  );

-- ──────────────────────────────────────────────────────────────
-- 2. Fix community_group_members SELECT RLS (tenant scoping)
--    Visible to: the member themself, anyone who shares the group's tenant,
--    or the group is public/platform-level. Fixes cross-church member leak.
-- ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can view community group members" ON public.community_group_members;
CREATE POLICY "Users can view community group members"
  ON public.community_group_members FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.community_groups cg
      WHERE cg.id = community_group_members.group_id
      AND (
        cg.tenant_id IS NULL
        OR cg.is_public = true
        OR cg.tenant_id::text = (
          SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
        )
      )
    )
  );

-- ──────────────────────────────────────────────────────────────
-- 3. Keep member_count in sync via triggers (joins/leaves + deletes)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_community_group_member_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.community_groups
    SET member_count = member_count + 1
    WHERE id = NEW.group_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.community_groups
    SET member_count = GREATEST(member_count - 1, 0)
    WHERE id = OLD.group_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_community_group_member_count ON public.community_group_members;
CREATE TRIGGER trg_community_group_member_count
  AFTER INSERT OR DELETE ON public.community_group_members
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_community_group_member_count();