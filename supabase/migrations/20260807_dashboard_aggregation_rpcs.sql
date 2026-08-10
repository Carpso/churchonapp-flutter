-- ═══════════════════════════════════════════════════════════════════════════════
-- DASHBOARD AGGREGATION & REPORTING RPCS
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Get Node Aggregated Stats (Sum of children)
CREATE OR REPLACE FUNCTION public.get_node_aggregated_stats(p_node_id UUID)
RETURNS JSONB
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
    -- Get all leaf nodes (branches) under this node (recursive)
    WITH RECURSIVE tree AS (
        SELECT id, tenant_id FROM hierarchy_nodes WHERE id = p_node_id
        UNION ALL
        SELECT hn.id, hn.tenant_id FROM hierarchy_nodes hn JOIN tree t ON hn.parent_node_id = t.id
    )
    SELECT ARRAY_AGG(id) INTO v_child_nodes FROM tree WHERE tenant_id IS NOT NULL;

    -- Aggregate stats from churches linked to these nodes
    IF v_child_nodes IS NOT NULL THEN
        SELECT COUNT(*) INTO v_branch_count FROM hierarchy_nodes WHERE id = ANY(v_child_nodes);

        -- Attendance sum (MTD)
        SELECT COUNT(*) INTO v_total_attendance
        FROM attendance_logs al
        JOIN hierarchy_nodes hn ON hn.tenant_id::text = al.tenant_id::text
        WHERE hn.id = ANY(v_child_nodes)
        AND al.created_at >= date_trunc('month', now());

        -- Giving sum (MTD)
        SELECT COALESCE(SUM(amount), 0) INTO v_total_giving
        FROM transactions t
        JOIN hierarchy_nodes hn ON hn.tenant_id::text = t.tenant_id::text
        WHERE hn.id = ANY(v_child_nodes)
        AND t.status = 'settled'
        AND t.created_at >= date_trunc('month', now());
    END IF;

    RETURN jsonb_build_object(
        'branches', v_branch_count,
        'attendance', v_total_attendance,
        'giving', v_total_giving
    );
END;
$$;

-- 2. Local Pastor Monthly Report Verification
CREATE TABLE IF NOT EXISTS public.local_monthly_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    month_year DATE NOT NULL,
    verified_by UUID NOT NULL REFERENCES auth.users(id),
    total_attendance INTEGER,
    total_tithes NUMERIC,
    total_offerings NUMERIC,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(tenant_id, month_year)
);

ALTER TABLE public.local_monthly_verifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Pastors can manage local verifications" ON public.local_monthly_verifications;
CREATE POLICY "Pastors can manage local verifications" ON public.local_monthly_verifications
    FOR ALL TO authenticated
    USING (
        EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = local_monthly_verifications.tenant_id AND p.role IN ('pastor', 'admin', 'superadmin'))
    );
