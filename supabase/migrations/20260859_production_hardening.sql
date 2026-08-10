-- ═══════════════════════════════════════════════════════════════════════════════
-- PRODUCTION HARDENING: ministry schedules, missions table, network reporting
-- RPCs, scale indexes, profiles.tenant_id type alignment
-- Idempotent. Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. MISSING MISSIONS TABLE (queried by bishop dashboard but never created)
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
       FOR SELECT ON public.missions
       TO authenticated
       USING (
          organization_id IN (SELECT organization_id FROM profiles WHERE id = auth.uid())
          OR tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
       );
   DROP POLICY IF EXISTS "missions: authors write" ON public.missions;
   CREATE POLICY "missions: authors write"
       FOR INSERT ON public.missions
       TO authenticated
       WITH CHECK (
          created_by = auth.uid()
          OR tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
       );
   DROP POLICY IF EXISTS "missions: authors update" ON public.missions;
   CREATE POLICY "missions: authors update"
       FOR UPDATE
       TO authenticated
       USING (created_by = auth.uid() OR tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
       WITH CHECK (created_by = auth.uid() OR tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()));
END $$;

-- 2. MINISTRY SCHEDULES (persistent, tenant-scoped — replaces in-memory-only notifier)
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
CREATE INDEX IF NOT EXISTS idx_ministry_schedules_tenant_date ON public.ministry_schedules (tenant_id, scheduled_for DESC);
CREATE INDEX IF NOT EXISTS idx_ministry_schedules_month ON public.ministry_schedules (tenant_id, date_trunc('month', scheduled_for));

DO $$
BEGIN
   DROP POLICY IF EXISTS "ministry_schedules: tenants see own schedules" ON public.ministry_schedules;
   CREATE POLICY "ministry_schedules: tenants see own schedules"
       FOR ALL ON public.ministry_schedules
       TO authenticated
       USING (tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
       WITH CHECK (tenant_id IN (SELECT tenant_id FROM profiles WHERE id = auth.uid()));
END $$;

-- 3. NETWORK REPORTING RPCS (server-side aggregation — replaces client IN-clause scans)

-- 3a. Missions across an entire organization (single round-trip, bounded)
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

-- 3b. Monthly tithe/giving sum for a single church (replaces unbounded client-side scan)
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
    WHERE t.tenant_id = p_tenant_id::text
      AND t.type IN ('tithe', 'giving', 'offering')
      AND t.status = 'settled'
      AND t.created_at >= p_start
      AND t.created_at <= p_end + interval '1 day';
    RETURN v_sum;
END;
$$;

-- 3c. Monthly stats for a church (attendance MTD/prev, tithes MTD, member count)
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
    WHERE t.tenant_id = p_tenant_id::text
      AND t.type IN ('tithe', 'giving', 'offering')
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

-- 3d. Per-church member counts within an organization (bounded; replaces full-profiles scan)
CREATE OR REPLACE FUNCTION public.get_organization_church_member_counts(p_org_id UUID)
RETURNS TABLE (church_id UUID, church_name TEXT, member_count BIGINT)
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
    LEFT JOIN public.profiles p ON p.tenant_id = c.id::text
    WHERE c.organization_id = p_org_id
    GROUP BY c.id, c.name
    ORDER BY c.created_at DESC;
END;
$$;

-- 4. PERFORMANCE INDEXES (scale to mega-churches & networks)

-- Branches list under an organization (bishop dashboard, bounded)
CREATE INDEX IF NOT EXISTS idx_churches_organization_active ON public.churches (organization_id, created_at DESC);

-- Financial dashboards: time-range queries by tenant
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_created ON public.transactions (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_type_status ON public.transactions (tenant_id, type, status);

-- Attendance MTD/month queries by tenant
CREATE INDEX IF NOT EXISTS idx_attendance_tenant_created ON public.attendance_logs (tenant_id, created_at);

-- Member directory / role-based lookups by tenant
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_role ON public.profiles (tenant_id, role);

-- Hierarchy tree traversal by organization
CREATE INDEX IF NOT EXISTS idx_hierarchy_nodes_org_parent ON public.hierarchy_nodes (organization_id, parent_node_id);

-- Ministries listing by tenant
CREATE INDEX IF NOT EXISTS idx_ministries_tenant_name ON public.ministries (tenant_id, name);

-- 5. profiles.tenant_id TYPE ALIGNMENT (TEXT -> UUID) + FK enforcement
-- Validates first; aborts cleanly if any value is not a valid UUID.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'profiles' AND column_name = 'tenant_id'
                 AND data_type = 'text') THEN
        IF EXISTS (SELECT 1 FROM profiles WHERE tenant_id IS NOT NULL AND tenant_id::uuid IS NULL) THEN
            RAISE EXCEPTION 'profiles.tenant_id contains non-UUID values — fix data before type migration';
        END IF;
    END IF;
END $$;

-- Idempotent: no-op if already uuid; casts cleanly if text-with-valid-uuids
ALTER TABLE profiles ALTER COLUMN tenant_id TYPE uuid USING tenant_id::uuid;

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_tenant_id_fkey;
ALTER TABLE profiles ADD CONSTRAINT profiles_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL;
