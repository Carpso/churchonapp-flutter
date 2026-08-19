-- 20260920: get_church_member_counts RPC for the Interchurch Network screen.
-- Profiles are NOT FK-linked to churches (tenant_id is text), so the client
-- cannot join churches -> profiles. This RPC returns per-church member counts
-- in one call, avoiding N+1 queries and profile-scoped RLS joins.

CREATE OR REPLACE FUNCTION public.get_church_member_counts()
RETURNS TABLE (church_id UUID, member_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id::uuid AS church_id, COUNT(p.id)::BIGINT AS member_count
  FROM churches t
  LEFT JOIN profiles p ON p.tenant_id::text = t.id::text
  GROUP BY t.id
$$;

REVOKE EXECUTE ON FUNCTION public.get_church_member_counts() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_church_member_counts() TO authenticated;
-- Giving overview perf: coa_payments.metadata tenant lookups need a GIN index
CREATE INDEX IF NOT EXISTS idx_coa_payments_metadata_tenant
  ON public.coa_payments USING GIN ((metadata -> 'tenant_id'));
