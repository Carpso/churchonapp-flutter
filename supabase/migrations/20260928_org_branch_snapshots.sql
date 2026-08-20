-- 20260928_org_branch_snapshots.sql
-- Single server-side call returning per-branch member / attendance / giving
-- snapshots for an org (bishop "All Branches" view). Replaces N sequential
-- get_church_monthly_stats calls in the bishop dashboard.
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
                             AND t.status = 'settled'
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