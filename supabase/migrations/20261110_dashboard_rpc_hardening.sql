-- 20261110: fix dashboard summaries for tenant-ID drift and authorize data.

CREATE OR REPLACE FUNCTION public.get_church_service_summary(p_tenant_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_month_start DATE := date_trunc('month', now())::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
    AND (p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin')
      OR p.tenant_id=p_tenant_id::text)) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;
  RETURN jsonb_build_object(
    'service_count', (SELECT count(*) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start),
    'attendance', (SELECT coalesce(sum(sr.attendance),0) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start),
    'offering', (SELECT coalesce(sum(sr.offering),0) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start),
    'visitors', (SELECT coalesce(sum(sr.visitors),0) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start),
    'salvations', (SELECT coalesce(sum(sr.salvations),0) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start),
    'online_viewers', (SELECT coalesce(sum(sr.online_viewers),0) FROM public.service_reports sr
      WHERE sr.tenant_id::text=p_tenant_id::text AND sr.created_at >= v_month_start)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_church_service_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_service_summary(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_organization_service_summary(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_month_start DATE := date_trunc('month', now())::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
    AND p.organization_id::text=p_org_id::text
    AND p.role IN ('superadmin','coa_employee','bishop','apostle','general_secretary')) THEN
    RAISE EXCEPTION 'Not authorized for this organization';
  END IF;
  RETURN jsonb_build_object(
    'churches', (SELECT count(*) FROM public.churches c WHERE c.organization_id=p_org_id),
    'service_count', (SELECT count(*) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start),
    'attendance', (SELECT coalesce(sum(sr.attendance),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start),
    'offering', (SELECT coalesce(sum(sr.offering),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start),
    'visitors', (SELECT coalesce(sum(sr.visitors),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start),
    'salvations', (SELECT coalesce(sum(sr.salvations),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start),
    'online_viewers', (SELECT coalesce(sum(sr.online_viewers),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text=sr.tenant_id::text OR c.tenant_id::text=sr.tenant_id::text)
      WHERE c.organization_id=p_org_id AND sr.created_at >= v_month_start)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_church_giving_overview(p_tenant_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_month_start TIMESTAMPTZ := date_trunc('month', now()); v_total NUMERIC; v_givers JSONB := '[]'::jsonb; v_leader BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
    AND (p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin','treasurer') OR p.tenant_id=p_tenant_id::text)) INTO v_leader;
  IF NOT v_leader THEN RAISE EXCEPTION 'Not authorized for this tenant'; END IF;
  SELECT coalesce(sum(amount),0) INTO v_total FROM public.coa_payments
  WHERE metadata->>'tenant_id'=p_tenant_id::text AND status IN ('approved','completed','confirmed','settled') AND created_at>=v_month_start;
  SELECT coalesce(jsonb_agg(row_to_json(g) ORDER BY g.amount DESC),'[]'::jsonb) INTO v_givers FROM (
    SELECT p.full_name AS name, c.amount, c.created_at FROM public.coa_payments c JOIN public.profiles p ON p.id=c.user_id
    WHERE c.metadata->>'tenant_id'=p_tenant_id::text AND c.status IN ('approved','completed','confirmed','settled') AND c.created_at>=v_month_start
    ORDER BY c.amount DESC LIMIT 5
  ) g;
  RETURN jsonb_build_object('monthly_total',v_total,'recent_givers',v_givers);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_church_giving_overview(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_giving_overview(UUID) TO authenticated;
