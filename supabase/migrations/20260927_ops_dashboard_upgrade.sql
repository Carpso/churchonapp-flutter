-- 20260927_ops_dashboard_upgrade.sql
-- Ops dashboards upgrade:
--   1. get_org_giving_series      - monthly settled-giving trend for an org (bishop/network view)
--   2. get_church_giving_series   - monthly settled-giving trend for a single church (finance dashboard)
--   3. link_church_to_org / unlink_church_from_org - safe church<->organization linking (RLS-gated)
--   4. get_platform_revenue_summary - superadmin/COA platform revenue (replaces unbounded client-side sums)
--   5. get_rider_summary          - rider lifetime trips/fare/distance + active trip
--   6. Seed "Church On App HQ" organization + link Rock Of Ages Chapel Kabulonga to it
--
-- FK map (matches 20260925):
--   profiles.tenant_id (text) -> tenants.id; churches.tenant_id -> tenants.id
--   transactions.tenant_id    -> tenants.id; ride_bookings.rider_id -> profiles.id

-- ============================================================
-- 1. get_org_giving_series
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
          AND t.status = 'settled'
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
-- 2. get_church_giving_series
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
          AND t.status = 'settled'
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
-- 3. link_church_to_org / unlink_church_from_org
--    Gate: superadmin/COA OR an org leader whose own church is in p_org_id.
-- ============================================================
CREATE OR REPLACE FUNCTION public.link_church_to_org(p_church_id uuid, p_org_id uuid)
RETURNS void
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

    UPDATE public.churches
    SET organization_id = p_org_id
    WHERE id = p_church_id;
END;
$$;

REVOKE ALL ON FUNCTION public.link_church_to_org(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_church_to_org(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_church_from_org(p_church_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id uuid;
BEGIN
    SELECT organization_id INTO v_org_id FROM public.churches WHERE id = p_church_id;
    IF v_org_id IS NULL THEN
        RETURN;
    END IF;

    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.tenant_id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = v_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    UPDATE public.churches
    SET organization_id = NULL
    WHERE id = p_church_id;
END;
$$;

REVOKE ALL ON FUNCTION public.unlink_church_from_org(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_church_from_org(uuid) TO authenticated;

-- ============================================================
-- 4. get_platform_revenue_summary (superadmin / COA only)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_platform_revenue_summary(p_months int DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total numeric;
    v_month_total numeric;
    v_series jsonb := '[]'::jsonb;
    v_month date;
BEGIN
    IF NOT is_admin_or_employee() THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT COALESCE(SUM(platform_fee), 0) INTO v_total
    FROM (
        SELECT platform_fee FROM public.transactions WHERE platform_fee IS NOT NULL
        UNION ALL
        SELECT platform_fee FROM public.wallet_transactions WHERE platform_fee IS NOT NULL
    ) fees;

    FOR i IN 0..GREATEST(p_months, 1) - 1 LOOP
        v_month := (date_trunc('month', now()) - (i || ' months')::interval)::date;
        SELECT COALESCE(SUM(f.platform_fee), 0) INTO v_month_total
        FROM (
            SELECT platform_fee, created_at FROM public.transactions WHERE platform_fee IS NOT NULL
            UNION ALL
            SELECT platform_fee, created_at FROM public.wallet_transactions WHERE platform_fee IS NOT NULL
        ) f
        WHERE f.created_at >= v_month AND f.created_at < v_month + interval '1 month';
        v_series := v_series || jsonb_build_object(
            'month', to_char(v_month, 'YYYY-MM'),
            'total', v_month_total
        );
    END LOOP;

    RETURN jsonb_build_object('total_revenue', v_total, 'series', v_series);
END;
$$;

REVOKE ALL ON FUNCTION public.get_platform_revenue_summary(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_platform_revenue_summary(int) TO authenticated;

-- ============================================================
-- 5. get_rider_summary — lifetime stats for the rider dashboard
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_rider_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trips BIGINT;
    v_fare numeric;
    v_distance numeric;
    v_active jsonb;
BEGIN
    IF NOT (auth.uid() = p_user_id OR is_admin_or_employee()) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT COUNT(*), COALESCE(SUM(fare), 0), COALESCE(SUM(distance_km), 0)
    INTO v_trips, v_fare, v_distance
    FROM public.ride_bookings
    WHERE rider_id = p_user_id AND status = 'completed';

    SELECT jsonb_build_object('id', rb.id, 'status', rb.status, 'fare', rb.fare,
                              'pickup_location', rb.pickup_location, 'dropoff_location', rb.dropoff_location)
    INTO v_active
    FROM public.ride_bookings rb
    WHERE rb.rider_id = p_user_id AND rb.status IN ('pending','accepted','in_progress')
    ORDER BY rb.created_at DESC
    LIMIT 1;

    RETURN jsonb_build_object(
        'completed_trips', v_trips,
        'total_fare', v_fare,
        'total_distance_km', v_distance,
        'active_ride', v_active
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_rider_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_rider_summary(uuid) TO authenticated;

-- ============================================================
-- 6. Seed HQ organization + link Rock Of Ages Chapel Kabulonga
-- ============================================================
INSERT INTO public.organizations (id, name, created_at)
VALUES ('11111111-1111-4111-8111-111111111111', 'Church On App HQ', now())
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.churches
        WHERE id = 'a7d7ef90-5555-4444-9999-d8c9735d4b53'
          AND organization_id IS NULL
    ) THEN
        UPDATE public.churches
        SET organization_id = '11111111-1111-4111-8111-111111111111'
        WHERE id = 'a7d7ef90-5555-4444-9999-d8c9735d4b53';
    END IF;
END $$;