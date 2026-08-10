-- ═══════════════════════════════════════════════════════════════════════════════
-- ORGANIZATION CHURCH MEMBER COUNTS RPC
-- Bounded, server-side per-branch membership counts for an organization.
-- Replaces the unbounded `profiles.select('tenant_id')` scan on the apostle
-- dashboard with a single grouped aggregate.
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_organization_church_member_counts(p_org_id UUID)
RETURNS TABLE (
    church_id UUID,
    church_name TEXT,
    member_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id AS church_id,
        c.name AS church_name,
        COUNT(p.id) AS member_count
    FROM public.churches c
    LEFT JOIN public.profiles p
        ON p.tenant_id::uuid = c.id
    WHERE c.organization_id = p_org_id
    GROUP BY c.id, c.name
    ORDER BY c.name;
END;
$$;

-- SECURITY: never let anonymous (unauthenticated) users call this DEFINER function.
REVOKE EXECUTE ON FUNCTION public.get_organization_church_member_counts(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_organization_church_member_counts(UUID) TO authenticated;
