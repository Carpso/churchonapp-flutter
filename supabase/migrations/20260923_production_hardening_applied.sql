-- 20260923: PRODUCTION HARDENING (sections 1-4 only) — applied to live
-- Extracted from 20260859 (which was never applied: its section 5 type-cast
-- aborted on legacy non-UUID seed tenant_id values). This file creates the
-- missing missions + ministry_schedules tables, network-reporting RPCs and
-- scale indexes WITHOUT touching profiles.tenant_id's type.

-- 1. MISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.missions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    target_amount NUMERIC DEFAULT 0,
    raised_amount NUMERIC DEFAULT 0,
    status TEXT DEFAULT 'planning' CHECK (status IN ('planning','active','completed','cancelled')),
    start_date DATE,
    end_date DATE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_missions_org ON public.missions (organization_id);
CREATE INDEX IF NOT EXISTS idx_missions_tenant ON public.missions (tenant_id);

DO $$
BEGIN
   DROP POLICY IF EXISTS "missions: organization-scoped read" ON public.missions;
   CREATE POLICY "missions: organization-scoped read"
       ON public.missions FOR SELECT
       TO authenticated
       USING (
          organization_id IN (SELECT organization_id FROM profiles WHERE id = auth.uid())
          OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
       );
   DROP POLICY IF EXISTS "missions: authors write" ON public.missions;
   CREATE POLICY "missions: authors write"
       ON public.missions FOR INSERT
       TO authenticated
       WITH CHECK (
          created_by = auth.uid()
          OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
       );
   DROP POLICY IF EXISTS "missions: authors update" ON public.missions;
   CREATE POLICY "missions: authors update"
       ON public.missions FOR UPDATE
       TO authenticated
       USING (created_by = auth.uid() OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
       WITH CHECK (created_by = auth.uid() OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()));
END $$;

-- 2. MINISTRY SCHEDULES
CREATE TABLE IF NOT EXISTS public.ministry_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    ministry_name TEXT NOT NULL,
    scheduled_for DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME,
    location TEXT,
    leader TEXT,
    notes TEXT,
    recurrence TEXT DEFAULT 'none' CHECK (recurrence IN ('none','weekly','monthly')),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.ministry_schedules ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_ministry_schedules_tenant_date ON public.ministry_schedules (tenant_id, scheduled_for DESC);
CREATE INDEX IF NOT EXISTS idx_ministry_schedules_month ON public.ministry_schedules ((scheduled_for::date), tenant_id);

DO $$
BEGIN
   DROP POLICY IF EXISTS "ministry_schedules: tenants see own schedules" ON public.ministry_schedules;
   CREATE POLICY "ministry_schedules: tenants see own schedules"
       ON public.ministry_schedules FOR ALL
       TO authenticated
       USING (tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
       WITH CHECK (tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()));
END $$;

-- 3a. Missions across an entire organization
CREATE OR REPLACE FUNCTION public.get_organization_missions(
    p_org_id UUID,
    p_limit INT DEFAULT 50,
    p_status TEXT DEFAULT 'all'
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    church_id UUID,
    church_name TEXT,
    status TEXT,
    target_amount NUMERIC,
    raised_amount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
REVOKE EXECUTE ON FUNCTION public.get_organization_missions(UUID, INT, TEXT) FROM anon;

-- 3b. Monthly tithe/giving sum for a single church
CREATE OR REPLACE FUNCTION public.get_church_monthly_tithes(
    p_tenant_id UUID,
    p_start DATE DEFAULT NULL,
    p_end DATE DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sum NUMERIC;
BEGIN
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
REVOKE EXECUTE ON FUNCTION public.get_church_monthly_tithes(UUID, DATE, DATE) FROM anon;

-- 3c. Monthly stats for a church
CREATE OR REPLACE FUNCTION public.get_church_monthly_stats(p_tenant_id UUID)
RETURNS JSONB
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
    SELECT COUNT(*) INTO v_att_mtd
    FROM public.attendance_logs
    WHERE tenant_id = p_tenant_id::text
      AND created_at >= v_first;

    SELECT COUNT(*) INTO v_att_prev
    FROM public.attendance_logs
    WHERE tenant_id = p_tenant_id::text
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
REVOKE EXECUTE ON FUNCTION public.get_church_monthly_stats(UUID) FROM anon;

-- 4. PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_churches_organization_active ON public.churches (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_created ON public.transactions (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_category_status ON public.transactions (tenant_id, category, status);
CREATE INDEX IF NOT EXISTS idx_attendance_tenant_created ON public.attendance_logs (tenant_id, created_at);
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_role ON public.profiles (tenant_id, role);
CREATE INDEX IF NOT EXISTS idx_hierarchy_nodes_org_parent ON public.hierarchy_nodes (organization_id, parent_node_id);
CREATE INDEX IF NOT EXISTS idx_ministries_tenant_name ON public.ministries (tenant_id, name);