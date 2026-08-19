-- 20260925_fix_bishop_rpc_gates.sql
-- Root cause: profiles.tenant_id stores the TENANTS.id (text), but the
-- org-leadership gates in get_organization_stats / get_node_aggregated_stats
-- joined `churches.id::text = me.tenant_id`. For any real church where
-- churches.id != churches.tenant_id (most registered churches), bishops
-- always hit `RAISE EXCEPTION 'Not authorized'` -> bishop dashboard showed
-- an error/retry loop ("just reloading").
--
-- Fix: join through churches.tenant_id (which IS the tenants.id).
-- FK reference map used in this file:
--   profiles.tenant_id (text)       -> tenants.id
--   churches.tenant_id              -> tenants.id
--   transactions.tenant_id          -> tenants.id
--   attendance_logs.tenant_id       -> tenants.id
--   hierarchy_nodes.tenant_id       -> churches.id
--   missions.tenant_id              -> churches.id
--   live_streams.church_id          -> churches.id
--
-- Also added:
--   * get_organization_missions gets an org-membership auth gate (was open
--     to ANY authenticated user - data leak).
--   * get_church_monthly_stats gets a tenant-membership gate (was open to
--     ANY authenticated user - data leak).

-- ============================================================
-- 1. get_organization_stats — fix auth gate join
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_organization_stats(p_org_id uuid)
RETURNS jsonb
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
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.tenant_id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = p_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*) INTO v_member_count FROM public.profiles p JOIN public.churches c ON c.tenant_id::text = p.tenant_id WHERE c.organization_id = p_org_id;
    SELECT COUNT(*) INTO v_branch_count FROM public.churches WHERE organization_id = p_org_id;
    SELECT COALESCE(SUM(amount), 0) INTO v_total_giving FROM public.transactions t JOIN public.churches c ON c.tenant_id = t.tenant_id WHERE c.organization_id = p_org_id AND t.status = 'settled' AND t.created_at >= date_trunc('month', now());
    SELECT COUNT(*) INTO v_active_streams FROM public.live_streams ls JOIN public.churches c ON c.id = ls.church_id WHERE c.organization_id = p_org_id AND ls.status = 'live';
    RETURN jsonb_build_object('members', v_member_count, 'branches', v_branch_count, 'monthly_giving', v_total_giving, 'active_streams', v_active_streams);
END;
$$;

REVOKE ALL ON FUNCTION public.get_organization_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_stats(uuid) TO authenticated;

-- ============================================================
-- 2. get_node_aggregated_stats — fix auth gate joins (both the
--    caller's church join and the node->church join)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_node_aggregated_stats(p_node_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_attendance BIGINT := 0;
    v_total_giving NUMERIC := 0;
    v_branch_count BIGINT := 0;
    v_child_nodes UUID[];
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.tenant_id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND EXISTS (
                  SELECT 1 FROM public.hierarchy_nodes hn
                  WHERE hn.id = p_node_id AND hn.tenant_id = my_c.id
              )
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    WITH RECURSIVE tree AS (
        SELECT id, tenant_id FROM hierarchy_nodes WHERE id = p_node_id
        UNION ALL
        SELECT hn.id, hn.tenant_id FROM hierarchy_nodes hn JOIN tree t ON hn.parent_node_id = t.id
    )
    SELECT ARRAY_AGG(id) INTO v_child_nodes FROM tree WHERE tenant_id IS NOT NULL;
    IF v_child_nodes IS NOT NULL THEN
        SELECT COUNT(*) INTO v_branch_count FROM hierarchy_nodes WHERE id = ANY(v_child_nodes);
        SELECT COUNT(*) INTO v_total_attendance
        FROM attendance_logs al
        JOIN hierarchy_nodes hn ON hn.id = ANY(v_child_nodes)
        JOIN churches c ON c.id = hn.tenant_id
        WHERE al.tenant_id = c.tenant_id
          AND al.created_at >= date_trunc('month', now());
        SELECT COALESCE(SUM(amount), 0) INTO v_total_giving
        FROM transactions t
        JOIN hierarchy_nodes hn ON hn.id = ANY(v_child_nodes)
        JOIN churches c ON c.id = hn.tenant_id
        WHERE t.tenant_id = c.tenant_id
          AND t.status = 'settled'
          AND t.created_at >= date_trunc('month', now());
    END IF;
    RETURN jsonb_build_object('branches', v_branch_count, 'attendance', v_total_attendance, 'giving', v_total_giving);
END;
$$;

REVOKE ALL ON FUNCTION public.get_node_aggregated_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_node_aggregated_stats(uuid) TO authenticated;

-- ============================================================
-- 3. get_organization_missions — add auth gate (was open to any
--    authenticated user). missions.tenant_id -> churches.id.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_organization_missions(p_org_id uuid, p_limit int DEFAULT 50, p_status text DEFAULT 'all')
RETURNS TABLE (
    id uuid,
    title text,
    church_id uuid,
    church_name text,
    status text,
    target_amount numeric,
    raised_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.tenant_id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = p_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    RETURN QUERY
    SELECT
        m.id,
        m.title,
        m.tenant_id AS church_id,
        (SELECT name FROM churches c WHERE c.id = m.tenant_id) AS church_name,
        m.status,
        COALESCE(m.target_amount, 0) AS target_amount,
        COALESCE(m.raised_amount, 0) AS raised_amount
    FROM public.missions m
    JOIN public.churches c ON c.id = m.tenant_id
    WHERE c.organization_id = p_org_id
      AND (p_status = 'all' OR m.status = p_status)
    ORDER BY m.created_at DESC
    LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_organization_missions(uuid, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_missions(uuid, int, text) TO authenticated;

-- ============================================================
-- 4. get_church_monthly_stats — add tenant-membership gate (was
--    open to ANY authenticated user). Tenant members + leadership
--    + platform admins may read their own church's stats.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_church_monthly_stats(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_att_mtd BIGINT;
    v_att_prev BIGINT;
    v_tithes NUMERIC;
    v_members BIGINT;
    v_first DATE := date_trunc('month', now())::date;
    v_prev_start DATE := (date_trunc('month', now()) - interval '1 month')::date;
    v_prev_end DATE := (date_trunc('month', now()) - interval '1 day')::date;
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            WHERE me.id = auth.uid()
              AND me.tenant_id = p_tenant_id::text
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*) INTO v_att_mtd
    FROM public.attendance_logs
    WHERE tenant_id = p_tenant_id
      AND created_at >= v_first;

    SELECT COUNT(*) INTO v_att_prev
    FROM public.attendance_logs
    WHERE tenant_id = p_tenant_id
      AND created_at >= v_prev_start
      AND created_at <= v_prev_end;

    SELECT COUNT(*) INTO v_members
    FROM public.profiles
    WHERE tenant_id = p_tenant_id::text;

    SELECT COALESCE(SUM(amount), 0) INTO v_tithes
    FROM public.transactions t
    WHERE t.tenant_id = p_tenant_id
      AND t.category IN ('tithe', 'giving', 'offering')
      AND t.status = 'settled'
      AND t.created_at >= v_first;

    RETURN jsonb_build_object(
        'attendance_mtd', v_att_mtd,
        'attendance_previous', v_att_prev,
        'tithes_mtd', v_tithes,
        'members', v_members
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_church_monthly_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_monthly_stats(uuid) TO authenticated;