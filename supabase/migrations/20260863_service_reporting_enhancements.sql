-- ═══════════════════════════════════════════════════════════════════════════════
-- P5: TENANT REPORTING SYSTEM ENHANCEMENTS
-- Adds enterprise-scale service reporting fields (visitors, salvations,
-- online viewers, ministries participation) + organization-wide aggregation
-- RPCs that feed the bishop/apostle/general-secretary dashboards.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. New columns on service_reports (backward-compatible additions)
ALTER TABLE public.service_reports
  ADD COLUMN IF NOT EXISTS service_date DATE,
  ADD COLUMN IF NOT EXISTS visitors INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS salvations INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS online_viewers INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ministries_active INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- 2. Per-church service summary (last 30 days, current month)
CREATE OR REPLACE FUNCTION public.get_church_service_summary(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_service_count INT;
    v_total_attendance INT;
    v_total_offering NUMERIC;
    v_total_visitors INT;
    v_total_salvations INT;
    v_total_online_viewers INT;
    v_month_start DATE := date_trunc('month', now())::date;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(attendance), 0), COALESCE(SUM(offering), 0),
           COALESCE(SUM(visitors), 0), COALESCE(SUM(salvations), 0), COALESCE(SUM(online_viewers), 0)
    INTO v_service_count, v_total_attendance, v_total_offering,
         v_total_visitors, v_total_salvations, v_total_online_viewers
    FROM public.service_reports
    WHERE tenant_id = p_tenant_id::text
      AND (service_date >= v_month_start OR service_date IS NULL)
      AND created_at >= v_month_start;

    RETURN jsonb_build_object(
        'service_count', v_service_count,
        'attendance', v_total_attendance,
        'offering', v_total_offering,
        'visitors', v_total_visitors,
        'salvations', v_total_salvations,
        'online_viewers', v_total_online_viewers
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_church_service_summary(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_church_service_summary(UUID) TO authenticated;

-- 3. Organization-wide service aggregation (all churches in an organization,
--    current month). Feeds the bishop/apostle network dashboards.
CREATE OR REPLACE FUNCTION public.get_organization_service_summary(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_service_count INT;
    v_total_attendance INT;
    v_total_offering NUMERIC;
    v_total_visitors INT;
    v_total_salvations INT;
    v_total_online_viewers INT;
    v_church_count INT;
    v_month_start DATE := date_trunc('month', now())::date;
BEGIN
    SELECT COUNT(*) INTO v_church_count FROM public.churches WHERE organization_id = p_org_id;

    SELECT COUNT(*), COALESCE(SUM(sr.attendance), 0), COALESCE(SUM(sr.offering), 0),
           COALESCE(SUM(sr.visitors), 0), COALESCE(SUM(sr.salvations), 0), COALESCE(SUM(sr.online_viewers), 0)
    INTO v_service_count, v_total_attendance, v_total_offering,
         v_total_visitors, v_total_salvations, v_total_online_viewers
    FROM public.service_reports sr
    JOIN public.churches c ON c.id::text = sr.tenant_id
    WHERE c.organization_id = p_org_id
      AND (sr.service_date >= v_month_start OR sr.service_date IS NULL)
      AND sr.created_at >= v_month_start;

    RETURN jsonb_build_object(
        'churches', v_church_count,
        'service_count', v_service_count,
        'attendance', v_total_attendance,
        'offering', v_total_offering,
        'visitors', v_total_visitors,
        'salvations', v_total_salvations,
        'online_viewers', v_total_online_viewers
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) TO authenticated;
