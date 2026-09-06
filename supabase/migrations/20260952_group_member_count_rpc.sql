-- 20260952 — group member_count RPC
--
-- joinGroup/leaveGroup insert/delete community_group_members rows but never
-- updated community_groups.member_count (the UI's "N members" stayed stale
-- until re-fetch). A direct UPDATE is blocked by RLS (community_groups_update
-- only allows admin/pastor/bishop), so route the bump through a SECURITY
-- DEFINER RPC available to any authenticated member.

CREATE OR REPLACE FUNCTION public.bump_group_member_count(p_group_id uuid, p_delta int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.community_groups
  SET member_count = GREATEST(0, COALESCE(member_count, 0) + p_delta)
  WHERE id = p_group_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.bump_group_member_count(uuid, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bump_group_member_count(uuid, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.bump_group_member_count(uuid, int) TO authenticated;