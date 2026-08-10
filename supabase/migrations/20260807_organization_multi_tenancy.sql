-- ═══════════════════════════════════════════════════════════════════════════════
-- ORGANIZATION MULTI-TENANCY MIGRATION
-- Enables "Bishops" to manage multiple churches and quizzes at a network level.
-- Supports many independent church organizations on the same platform.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. ENHANCE PROFILES WITH ORGANIZATION_ID
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL;

-- 2. ENHANCE CHURCH COMPETITIONS WITH ORGANIZATION_ID
-- Allows "National Quizzes" that span all branches in an organization.
ALTER TABLE public.church_competitions ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.church_competitions ALTER COLUMN tenant_id DROP NOT NULL; -- Can be either tenant_id OR organization_id

-- 3. ENSURE TENANTS BELONG TO ORGANIZATIONS
-- If organization_id is missing on churches, link them to a default one or leave for manual setup.
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL;

-- 4. RLS POLICIES FOR MULTI-TENANT OVERSIGHT

-- [TENANTS] Bishops can see all churches in their organization
DROP POLICY IF EXISTS "Bishops can view organization churches" ON public.churches;
CREATE POLICY "Bishops can view organization churches" ON public.churches
    FOR SELECT TO authenticated
    USING (
        organization_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND p.organization_id = churches.organization_id
            AND p.role IN ('bishop', 'general_secretary', 'general_treasurer', 'superadmin')
        )
    );

-- [TRANSACTIONS] Organization leaders can see network-wide finances
DROP POLICY IF EXISTS "Organization leaders view all transactions" ON public.transactions;
CREATE POLICY "Organization leaders view all transactions" ON public.transactions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles p
            JOIN public.churches c ON c.id = transactions.tenant_id
            WHERE p.id = auth.uid()
            AND p.organization_id = c.organization_id
            AND p.role IN ('bishop', 'general_treasurer', 'superadmin')
        )
    );

-- [QUIZ] Bishops can manage network-level competitions
DROP POLICY IF EXISTS "Bishops can manage organization quizzes" ON public.church_competitions;
CREATE POLICY "Bishops can manage organization quizzes" ON public.church_competitions
    FOR ALL TO authenticated
    USING (
        organization_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND p.organization_id = church_competitions.organization_id
            AND p.role IN ('bishop', 'superadmin')
        )
    );

-- 5. AGGREGATION FUNCTIONS FOR BISHOP DASHBOARD

-- Get organization-wide stats (Membership, Giving, Branches)
CREATE OR REPLACE FUNCTION public.get_organization_stats(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_member_count BIGINT;
    v_branch_count BIGINT;
    v_total_giving NUMERIC;
    v_active_streams BIGINT;
BEGIN
    -- Count all members in branches belonging to this org
    SELECT COUNT(*) INTO v_member_count
    FROM public.profiles p
    JOIN public.churches c ON c.id = p.tenant_id
    WHERE c.organization_id = p_org_id;

    -- Count branches
    SELECT COUNT(*) INTO v_branch_count
    FROM public.churches
    WHERE organization_id = p_org_id;

    -- Sum giving across all branches
    SELECT COALESCE(SUM(amount), 0) INTO v_total_giving
    FROM public.transactions t
    JOIN public.churches c ON c.id = t.tenant_id
    WHERE c.organization_id = p_org_id
    AND t.status = 'settled'
    AND t.created_at >= date_trunc('month', now());

    -- Active live streams across network
    SELECT COUNT(*) INTO v_active_streams
    FROM public.live_streams ls
    JOIN public.churches c ON c.id = ls.church_id
    WHERE c.organization_id = p_org_id
    AND ls.status = 'live';

    RETURN jsonb_build_object(
        'members', v_member_count,
        'branches', v_branch_count,
        'monthly_giving', v_total_giving,
        'active_streams', v_active_streams
    );
END;
$$;
