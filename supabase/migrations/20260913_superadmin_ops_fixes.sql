-- ═══════════════════════════════════════════════════════════════════════════════
-- 20260913 SUPERADMIN OPS FIXES
-- 1. KYC / verification RLS → is_admin_or_employee() (includes coa_employee)
-- 2. churches.is_active column + suspend/reactivate sync (tenant ↔ church)
-- 3. Service report summary RPCs: exclude announcements, robust month grouping
-- 4. Rock Of Ages Chapel Kabulonga = the ONLY active tenant on the platform
--    (user's home church; everything else deactivated)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── 1. KYC documents: admin UPDATE policy → shared helper (covers coa_employee) ──
DROP POLICY IF EXISTS "Employees can update kyc documents" ON public.kyc_documents;
CREATE POLICY "Employees can update kyc documents" ON public.kyc_documents
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_employee());

-- ── 2. Verification requests: SELECT + UPDATE → shared helper ──────────────────
DROP POLICY IF EXISTS "Employees can view all requests" ON public.verification_requests;
CREATE POLICY "Employees can view all requests" ON public.verification_requests
  FOR SELECT TO authenticated
  USING (public.is_admin_or_employee());

DROP POLICY IF EXISTS "Employees can update requests" ON public.verification_requests;
CREATE POLICY "Employees can update requests" ON public.verification_requests
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_employee());

-- ── 3a. churches.is_active column (mirror of tenants.is_active) ─────────────────
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- ── 3b. suspend_tenant / reactivate_tenant sync churches.is_active ──────────────
CREATE OR REPLACE FUNCTION public.suspend_tenant(p_tenant_id uuid, p_reason text DEFAULT NULL::text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL OR NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE public.tenants
  SET is_active = false
  WHERE id = p_tenant_id;

  UPDATE public.churches
  SET is_active = false
  WHERE tenant_id = p_tenant_id::text;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_suspended', 'tenants', p_tenant_id,
          jsonb_build_object('reason', p_reason));

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reactivate_tenant(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL OR NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE public.tenants
  SET is_active = true
  WHERE id = p_tenant_id;

  UPDATE public.churches
  SET is_active = true
  WHERE tenant_id = p_tenant_id::text;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_reactivated', 'tenants', p_tenant_id, '{}');

  RETURN true;
END;
$function$;

-- ── 4. Service report summaries: count only real services; group by effective date ──
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
      AND COALESCE(type, 'service') = 'service'
      AND COALESCE(service_date, created_at::date) >= v_month_start;

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
      AND COALESCE(sr.type, 'service') = 'service'
      AND COALESCE(sr.service_date, sr.created_at::date) >= v_month_start;

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

-- ── 5. Rock Of Ages Chapel Kabulonga = ONLY active tenant ───────────────────────
-- Activate the user's home church everywhere (tenants + churches + subscription).
UPDATE public.tenants
SET is_active = true
WHERE name ILIKE '%Rock Of Ages%Kabulonga%'
   OR name ILIKE '%Rock of Ages Chapel Kabulonga%';

UPDATE public.churches
SET is_active = true,
    is_verified = true,
    subscription_ends_at = GREATEST(COALESCE(subscription_ends_at, now()), now() + interval '10 years')
WHERE name ILIKE '%Rock Of Ages%Kabulonga%'
   OR name ILIKE '%Rock of Ages Chapel Kabulonga%';

-- Everything else: deactivated + unverified (only Rock Of Ages is selectable).
UPDATE public.tenants
SET is_active = false
WHERE is_active = true
  AND NOT (name ILIKE '%Rock Of Ages%Kabulonga%'
       OR name ILIKE '%Rock of Ages Chapel Kabulonga%');

UPDATE public.churches
SET is_active = false,
    is_verified = false
WHERE is_verified = true
  AND NOT (name ILIKE '%Rock Of Ages%Kabulonga%'
       OR name ILIKE '%Rock of Ages Chapel Kabulonga%');

-- NOTE: there are TWO "Rock Of Ages Chapel Kabulonga" rows (duplicates) and two
-- "Kabs" rows in tenants — both Rock Of Ages rows are activated; duplicates should
-- be merged manually from the dashboard (keep the one with member data).