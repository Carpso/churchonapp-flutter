-- 20261014 Server-Side Security Remediation
-- Fixes audit findings from the 2026-09-06 server-side security audit.
--
-- 1. Anon/PUBLIC EXECUTE revoked on SECURITY DEFINER functions.
-- 2. Auth gates added to 4 reader functions that returned money / member /
--    heatmap data to ANY unauthenticated caller (including anon).
-- 3. Removed `public`-role RLS policies with WITH CHECK (true) / USING (true)
--    or broad expressions; recreated as `authenticated` where the feature is
--    an authenticated in-app flow.
--
-- Applied live: 2026-09-06. Verified via pg_policies + has_function_privilege.

BEGIN;

-- ============================================================================
-- 1. FUNCTION GRANTS
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1a. Reader functions: add auth gates AND revoke PUBLIC/anon EXECUTE
--     (these returned ALL tenants' giving totals / member counts / heatmaps).
-- ---------------------------------------------------------------------------

-- get_church_monthly_tithes: only a leader of the tenant, or a COA-level
-- staff member, may read a church's settled giving totals.
CREATE OR REPLACE FUNCTION public.get_church_monthly_tithes(
    p_tenant_id uuid,
    p_start date DEFAULT NULL::date,
    p_end date DEFAULT NULL::date
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sum numeric;
    v_role text;
    v_tenant text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT role, tenant_id INTO v_role, v_tenant
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_role IN ('superadmin', 'super_admin', 'employee', 'coa_employee') THEN
        -- COA staff may read any tenant
        NULL;
    ELSIF v_role IN ('admin', 'pastor', 'bishop', 'apostle', 'prophet',
                     'general_secretary', 'treasurer', 'general_treasurer') THEN
        -- tenant leaders may only read their own tenant
        IF v_tenant <> p_tenant_id::text THEN
            RAISE EXCEPTION 'Not authorized for this tenant';
        END IF;
    ELSE
        RAISE EXCEPTION 'Not authorized';
    END IF;

    IF p_start IS NULL THEN
        p_start := date_trunc('month', now())::date;
    END IF;
    IF p_end IS NULL THEN
        p_end := (date_trunc('month', now()) + interval '1 month' - interval '1 day')::date;
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_sum
    FROM public.transactions t
    WHERE t.tenant_id = p_tenant_id
      AND t.category IN ('tithe', 'giving', 'offering')
      AND t.status = 'settled'
      AND t.created_at >= p_start
      AND t.created_at <= p_end + interval '1 day';

    RETURN v_sum;
END;
$$;

-- get_church_member_counts: authenticated members may browse network member
-- counts; anonymous requests get an empty result set.
CREATE OR REPLACE FUNCTION public.get_church_member_counts()
RETURNS TABLE (church_id uuid, member_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT t.id::uuid AS church_id, COUNT(p.id)::BIGINT AS member_count
    FROM public.churches t
    LEFT JOIN public.profiles p ON p.tenant_id::text = t.id::text
    GROUP BY t.id;
END;
$$;

-- get_prophetic_heatmap_data: authenticated leadership tool.
CREATE OR REPLACE FUNCTION public.get_prophetic_heatmap_data()
RETURNS TABLE (
    lat double precision,
    lng double precision,
    weight numeric,
    region_name text,
    member_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        ch.latitude AS lat,
        ch.longitude AS lng,
        GREATEST(1, (SELECT COUNT(*)::numeric FROM public.profiles p WHERE p.tenant_id = ch.tenant_id::text)) AS weight,
        ch.name AS region_name,
        (SELECT COUNT(*) FROM public.profiles p WHERE p.tenant_id = ch.tenant_id::text) AS member_count
    FROM public.churches ch
    WHERE ch.latitude IS NOT NULL AND ch.longitude IS NOT NULL
    ORDER BY member_count DESC;
END;
$$;

-- get_prophetic_heatmap_legacy: authenticated leadership tool.
CREATE OR REPLACE FUNCTION public.get_prophetic_heatmap_legacy()
RETURNS TABLE (
    lat double precision,
    lng double precision,
    weight numeric,
    region_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT g.lat, g.lng, GREATEST(0.5, g.weight) AS weight, g.region_name
    FROM public.growth_heatmap_data g;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_church_monthly_tithes(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_church_monthly_tithes(uuid, date, date) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_church_member_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_church_member_counts() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_prophetic_heatmap_data() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_legacy() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_prophetic_heatmap_legacy() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1b. Auth-guarded SECURITY DEFINER functions: revoke PUBLIC so anonymous
--     callers cannot even attempt them (they already enforce auth.uid()
--     inside, this is defense in depth).
-- ---------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.approve_role_assignment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_role_assignment(uuid, text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.elevate_user_role(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.elevate_user_role(uuid, text, text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.create_organization(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_organization(text) TO authenticated, service_role;

-- Helper predicates used inside RLS policies (executed as `authenticated`);
-- anonymous callers no longer get them.
REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_admin_or_employee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin_or_employee() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_church_pastor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_church_pastor(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1c. SECURITY DEFINER trigger functions: no direct EXECUTE for anyone.
--     PostgreSQL fires triggers regardless of EXECUTE grants, so revoking
--     from all roles keeps the triggers working while removing direct call.
-- ---------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.sync_role_to_auth_metadata() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_community_group_member_count() FROM PUBLIC;

-- Also drop explicit anon grants if they were ever added for these two
REVOKE EXECUTE ON FUNCTION public.sync_role_to_auth_metadata() FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_community_group_member_count() FROM anon;

-- ============================================================================
-- 2. RLS POLICY FIXES
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2a. emergency_contacts: SELECT was `public` USING (true) -> 83 rows of
--     PII (name/phone). Now authenticated + tenant/src-aware.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS emergency_contacts_select ON public.emergency_contacts;
CREATE POLICY emergency_contacts_select ON public.emergency_contacts
    FOR SELECT
    TO authenticated
    USING (
        tenant_id IS NULL
        OR tenant_id::text = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
              AND p.role IN ('superadmin', 'employee', 'coa_employee')
        )
    );

ALTER POLICY emergency_contacts_insert ON public.emergency_contacts TO authenticated;
ALTER POLICY emergency_contacts_update ON public.emergency_contacts TO authenticated;
ALTER POLICY emergency_contacts_delete ON public.emergency_contacts TO authenticated;

-- ---------------------------------------------------------------------------
-- 2b. notifications: drop public INSERT (WITH CHECK true) that let anon
--     inject notifications. Keep/re-scope the accurate authenticated policy.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS notifications_insert ON public.notifications;
ALTER POLICY notifications_select ON public.notifications TO authenticated;
ALTER POLICY notifications_update ON public.notifications TO authenticated;

-- ---------------------------------------------------------------------------
-- 2c. audit_logs: drop public INSERT (WITH CHECK true) so anon cannot write
--     audit records (log tampering).
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS audit_logs_insert ON public.audit_logs;
ALTER POLICY audit_logs_select ON public.audit_logs TO authenticated;

-- ---------------------------------------------------------------------------
-- 2d. service_reports: drop public INSERT (WITH CHECK true); scope the
--     remaining reporter/tenant policies to authenticated.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Pastors can submit service reports" ON public.service_reports;

ALTER POLICY "Authenticated users can submit service reports" ON public.service_reports TO authenticated;
ALTER POLICY service_reports_insert ON public.service_reports TO authenticated;
ALTER POLICY service_reports_select ON public.service_reports TO authenticated;
ALTER POLICY "Tenant members can view service reports" ON public.service_reports TO authenticated;
ALTER POLICY service_reports_update ON public.service_reports TO authenticated;
ALTER POLICY service_reports_delete ON public.service_reports TO authenticated;

-- ---------------------------------------------------------------------------
-- 2e. klips: drop public INSERT (WITH CHECK true) upload; scope reads.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Anyone can upload klips" ON public.klips;
ALTER POLICY "Anyone can view klips" ON public.klips TO authenticated;

-- ---------------------------------------------------------------------------
-- 2f. event_participating_churches / event_resources: drop public INSERT.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Hosts can add participating churches" ON public.event_participating_churches;
ALTER POLICY "Anyone can view participating churches" ON public.event_participating_churches TO authenticated;

DROP POLICY IF EXISTS "Hosts can insert event resources" ON public.event_resources;

-- ---------------------------------------------------------------------------
-- 2g. church_storage_usage: UPDATE was `public` USING (true); SELECT was
--     public. Restrict UPDATE to service_role (system/edge/RPCs bypass RLS
--     anyway), scope SELECT to authenticated.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "System can update storage usage" ON public.church_storage_usage;
CREATE POLICY "System can update storage usage" ON public.church_storage_usage
    FOR UPDATE
    TO service_role
    USING (true)
    WITH CHECK (true);

ALTER POLICY "Churches can read own storage usage" ON public.church_storage_usage TO authenticated;

-- ---------------------------------------------------------------------------
-- 2h. donor_segments: SELECT was public USING (true) (donor CRM data).
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS donor_segments_select ON public.donor_segments;
CREATE POLICY donor_segments_select ON public.donor_segments
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
              AND p.role IN ('superadmin', 'employee', 'coa_employee', 'admin')
              AND p.church_id = donor_segments.church_id
        )
    );
ALTER POLICY donor_segments_manage ON public.donor_segments TO authenticated;

-- ---------------------------------------------------------------------------
-- 2i. driver_locations: live GPS of drivers. Scope all to authenticated.
-- ---------------------------------------------------------------------------

ALTER POLICY driver_locations_select ON public.driver_locations TO authenticated;
ALTER POLICY driver_locations_update ON public.driver_locations TO authenticated;

-- ---------------------------------------------------------------------------
-- 2j. growth_heatmap_data: public reads removed.
-- ---------------------------------------------------------------------------

ALTER POLICY "Anyone can view heatmap data" ON public.growth_heatmap_data TO authenticated;
ALTER POLICY "Superadmins can manage heatmap data" ON public.growth_heatmap_data TO authenticated;

-- ---------------------------------------------------------------------------
-- 2k. fundraising contributions (money): drop public view/contribute.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Anyone can view contributions" ON public.fundraising_contributions;
ALTER POLICY "Users can contribute" ON public.fundraising_contributions TO authenticated;

-- ---------------------------------------------------------------------------
-- 2l. group contributions & groups (money + PII rows).
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Users can join groups" ON public.group_contribution_members;
ALTER POLICY "Members can view group members" ON public.group_contribution_members TO authenticated;

DROP POLICY IF EXISTS "Users can contribute to groups" ON public.group_contribution_payments;
ALTER POLICY "Anyone can view group payments" ON public.group_contribution_payments TO authenticated;
ALTER POLICY "Group members and leaders can view payments" ON public.group_contribution_payments TO authenticated;

ALTER POLICY "Anyone can view group members" ON public.group_members TO authenticated;
ALTER POLICY "Group admins can manage members" ON public.group_members TO authenticated;
ALTER POLICY "Users can join groups" ON public.group_members TO authenticated;

-- ---------------------------------------------------------------------------
-- 2m. events / sermons: manage policies were public (auth-gated inside).
-- ---------------------------------------------------------------------------

ALTER POLICY "Event hosts can manage own events" ON public.events TO authenticated;
ALTER POLICY "Authenticated users can create events" ON public.events TO authenticated;

ALTER POLICY "Church admins can manage sermons" ON public.sermons TO authenticated;
-- "Anyone can view sample sermons" (anon, church_id IS NULL) is INTENTIONAL —
-- public sample sermons on the web landing pages. Kept.

-- ---------------------------------------------------------------------------
-- 2n. social_posts: `public` SELECT was effectively USING (true) — leaked ALL
--     tenants' posts to anon. Drop; the authenticated tenant-scoped +
--     superadmin select policies remain. All writes scope to authenticated.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Anyone can view social posts" ON public.social_posts;

ALTER POLICY "Authenticated users can submit social posts" ON public.social_posts TO authenticated;
ALTER POLICY "Users can create own posts" ON public.social_posts TO authenticated;
ALTER POLICY "Users can update own posts" ON public.social_posts TO authenticated;
ALTER POLICY "Users can delete own posts" ON public.social_posts TO authenticated;
ALTER POLICY "Superadmins can moderate all posts" ON public.social_posts TO authenticated;

COMMIT;