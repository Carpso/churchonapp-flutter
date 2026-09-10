-- 20261032_fix_dashboard_settled_filters.sql
-- Root cause: every giving aggregate filtered `transactions.status = 'settled'`,
-- but NOTHING ever writes 'settled' on transactions — all giving write paths
-- (finance_service.logTransaction, insert_transaction_idempotent, lipila-settle)
-- record 'completed' (some 'failed'/'pending'). 'settled' is a coa_payments
-- payout status only. Net effect: "Giving This Month", giving trends, org series
-- and branch snapshots were permanently ZERO across the pastor dashboard,
-- bishop dashboard, finance hub and report creator.
--
-- Fix: transaction aggregates now count `status IN ('completed','settled')`
-- (safe: covers the real write status AND any legacy settled-marked rows).
-- coa_payments 'settled' filters are intentionally untouched.
--
-- Functions recreated (live definitions as of 2026-09-08):
--   get_organization_stats       (from 20260925_fix_bishop_rpc_gates)
--   get_node_aggregated_stats    (from 20260925)
--   get_church_monthly_stats     (from 20260925)
--   get_church_monthly_tithes    (from 20261014_server_security_remediation)
--   get_org_giving_series        (from 20260927_ops_dashboard_upgrade)
--   get_church_giving_series     (from 20260927)
--   get_org_branch_snapshots     (from 20260928_org_branch_snapshots)

-- ============================================================
-- 1. get_organization_stats
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
    SELECT COALESCE(SUM(amount), 0) INTO v_total_giving FROM public.transactions t JOIN public.churches c ON c.tenant_id = t.tenant_id WHERE c.organization_id = p_org_id AND t.status IN ('completed','settled') AND t.created_at >= date_trunc('month', now());
    SELECT COUNT(*) INTO v_active_streams FROM public.live_streams ls JOIN public.churches c ON c.id = ls.church_id WHERE c.organization_id = p_org_id AND ls.status = 'live';
    RETURN jsonb_build_object('members', v_member_count, 'branches', v_branch_count, 'monthly_giving', v_total_giving, 'active_streams', v_active_streams);
END;
$$;

REVOKE ALL ON FUNCTION public.get_organization_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_stats(uuid) TO authenticated;

-- ============================================================
-- 2. get_node_aggregated_stats
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
          AND t.status IN ('completed','settled')
          AND t.created_at >= date_trunc('month', now());
    END IF;
    RETURN jsonb_build_object('branches', v_branch_count, 'attendance', v_total_attendance, 'giving', v_total_giving);
END;
$$;

REVOKE ALL ON FUNCTION public.get_node_aggregated_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_node_aggregated_stats(uuid) TO authenticated;

-- ============================================================
-- 3. get_church_monthly_stats
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
      AND t.status IN ('completed','settled')
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

-- ============================================================
-- 4. get_church_monthly_tithes
-- ============================================================
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
      AND t.status IN ('completed','settled')
      AND t.created_at >= p_start
      AND t.created_at <= p_end + interval '1 day';

    RETURN v_sum;
END;
$$;

REVOKE ALL ON FUNCTION public.get_church_monthly_tithes(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_monthly_tithes(uuid, date, date) TO authenticated;

-- ============================================================
-- 5. get_org_giving_series
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_org_giving_series(p_org_id uuid, p_months int DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_series jsonb := '[]'::jsonb;
    v_month date;
    v_total numeric;
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

    FOR i IN 0..GREATEST(p_months, 1) - 1 LOOP
        v_month := (date_trunc('month', now()) - (i || ' months')::interval)::date;
        SELECT COALESCE(SUM(t.amount), 0) INTO v_total
        FROM public.transactions t
        JOIN public.churches c ON c.tenant_id = t.tenant_id
        WHERE c.organization_id = p_org_id
          AND t.status IN ('completed','settled')
          AND t.created_at >= v_month
          AND t.created_at < v_month + interval '1 month';
        v_series := v_series || jsonb_build_object(
            'month', to_char(v_month, 'YYYY-MM'),
            'total', v_total
        );
    END LOOP;

    RETURN v_series;
END;
$$;

REVOKE ALL ON FUNCTION public.get_org_giving_series(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_giving_series(uuid, int) TO authenticated;

-- ============================================================
-- 6. get_church_giving_series
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_church_giving_series(p_tenant_id uuid, p_months int DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_series jsonb := '[]'::jsonb;
    v_month date;
    v_total numeric;
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

    FOR i IN 0..GREATEST(p_months, 1) - 1 LOOP
        v_month := (date_trunc('month', now()) - (i || ' months')::interval)::date;
        SELECT COALESCE(SUM(amount), 0) INTO v_total
        FROM public.transactions t
        WHERE t.tenant_id = p_tenant_id
          AND t.category IN ('tithe', 'giving', 'offering')
          AND t.status IN ('completed','settled')
          AND t.created_at >= v_month
          AND t.created_at < v_month + interval '1 month';
        v_series := v_series || jsonb_build_object(
            'month', to_char(v_month, 'YYYY-MM'),
            'total', v_total
        );
    END LOOP;

    RETURN v_series;
END;
$$;

REVOKE ALL ON FUNCTION public.get_church_giving_series(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_giving_series(uuid, int) TO authenticated;

-- ============================================================
-- 7. get_org_branch_snapshots
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_org_branch_snapshots(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_snapshots jsonb;
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

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'church_id', c.id,
            'church_name', c.name,
            'is_verified', c.is_verified,
            'members', (SELECT COUNT(*) FROM public.profiles p WHERE p.tenant_id = c.tenant_id::text),
            'attendance_mtd', (SELECT COUNT(*) FROM public.attendance_logs al
                               WHERE al.tenant_id = c.tenant_id
                                 AND al.created_at >= date_trunc('month', now())),
            'tithes_mtd', (SELECT COALESCE(SUM(t.amount), 0) FROM public.transactions t
                           WHERE t.tenant_id = c.tenant_id
                             AND t.status IN ('completed','settled')
                             AND t.created_at >= date_trunc('month', now())
                             AND t.category IN ('tithe','giving','offering')),
            'service_reports_mtd', (SELECT COUNT(*) FROM public.service_reports sr
                                    WHERE sr.tenant_id = c.tenant_id
                                      AND sr.created_at >= date_trunc('month', now()))
        )
        ORDER BY c.name
    ), '[]'::jsonb) INTO v_snapshots
    FROM public.churches c
    WHERE c.organization_id = p_org_id;

    RETURN v_snapshots;
END;
$$;

REVOKE ALL ON FUNCTION public.get_org_branch_snapshots(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_branch_snapshots(uuid) TO authenticated;