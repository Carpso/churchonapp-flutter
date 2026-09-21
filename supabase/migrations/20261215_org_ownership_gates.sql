-- 20261212_org_ownership_gates.sql
-- Root cause of "bishop/pastor dashboards basic / organisation features not
-- working": every organisation rollup RPC authorised the caller ONLY via
-- `profiles.tenant_id -> churches.organization_id`. A bishop whose
-- organisation was created with them as `organizations.bishop_id` (and whose
-- `profiles.organization_id` / church link drifted) therefore failed the gate
-- and every section silently degraded to empty. This migration introduces a
-- single central org-ownership helper and routes every org rollup through it.
--
-- is_org_owner(p_org_id) is TRUE when ANY of:
--   * platform staff (is_admin_or_employee)
--   * the caller IS bishop_id / secretary_id / treasurer_id of the org
--   * the caller's church is linked to the org (churches.organization_id)
--
-- SECURITY DEFINER + SET search_path = public + REVOKE FROM anon/public.

CREATE OR REPLACE FUNCTION public.is_org_owner(p_org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_tid text;
BEGIN
    IF v_uid IS NULL OR p_org_id IS NULL THEN
        RETURN false;
    END IF;
    IF public.is_admin_or_employee() THEN
        RETURN true;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.organizations o
        WHERE o.id = p_org_id
          AND (o.bishop_id = v_uid OR o.secretary_id = v_uid OR o.treasurer_id = v_uid)
    ) THEN
        RETURN true;
    END IF;
    SELECT p.tenant_id INTO v_tid FROM public.profiles p WHERE p.id = v_uid;
    IF v_tid IS NULL THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM public.churches c
        WHERE c.tenant_id::text = v_tid AND c.organization_id = p_org_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.is_org_owner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_org_owner(uuid) TO authenticated, service_role;

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
    IF NOT public.is_org_owner(p_org_id) THEN
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
-- 2. get_org_giving_series
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
    IF NOT public.is_org_owner(p_org_id) THEN
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
-- 3. get_org_branch_snapshots
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
    IF NOT public.is_org_owner(p_org_id) THEN
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

-- ============================================================
-- 4. get_organization_service_summary
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_organization_service_summary(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_month_start DATE := date_trunc('month', now())::date;
BEGIN
  IF NOT public.is_org_owner(p_org_id) THEN
    RAISE EXCEPTION 'Not authorized for this organization';
  END IF;
  RETURN jsonb_build_object(
    'churches', (SELECT count(*) FROM public.churches c WHERE c.organization_id = p_org_id),
    'service_count', (SELECT count(*) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start),
    'attendance', (SELECT coalesce(sum(sr.attendance),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start),
    'offering', (SELECT coalesce(sum(sr.offering),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start),
    'visitors', (SELECT coalesce(sum(sr.visitors),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start),
    'salvations', (SELECT coalesce(sum(sr.salvations),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start),
    'online_viewers', (SELECT coalesce(sum(sr.online_viewers),0) FROM public.service_reports sr JOIN public.churches c
      ON (c.id::text = sr.tenant_id::text OR c.tenant_id::text = sr.tenant_id::text)
      WHERE c.organization_id = p_org_id AND sr.created_at >= v_month_start)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) TO authenticated;

-- ============================================================
-- 5. get_organization_missions
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
    IF NOT public.is_org_owner(p_org_id) THEN
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
-- 6. get_basket_summary — org path now ownership-gated (was church-link only)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_basket_summary(
  p_tenant_id text DEFAULT NULL,
  p_org_id    uuid DEFAULT NULL,
  p_days      int  DEFAULT 30
)
RETURNS TABLE (
  basket_type_id uuid,
  basket_name    text,
  basket_code    text,
  scope          text,
  sessions       bigint,
  total_amount   numeric,
  last_taken_at  timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;

  IF p_org_id IS NOT NULL THEN
    IF NOT public.is_org_owner(p_org_id) THEN
      RAISE EXCEPTION 'different_organisation';
    END IF;
  ELSE
    IF p_tenant_id IS NOT NULL AND p_tenant_id <> v_tid
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_uid
                        AND p.role IN ('superadmin','super_admin','coa_employee','employee')) THEN
      RAISE EXCEPTION 'not_authorised';
    END IF;
  END IF;

  RETURN QUERY
  SELECT s.basket_type_id,
         COALESCE(s.basket_name, bt.name, 'Offering') AS basket_name,
         bt.code AS basket_code,
         CASE WHEN bt.tenant_id IS NULL THEN 'organisation' ELSE 'tenant' END AS scope,
         count(*)::bigint AS sessions,
         COALESCE(sum(s.total_amount), 0) AS total_amount,
         max(s.opened_at) AS last_taken_at
  FROM public.offering_sessions s
  LEFT JOIN public.offering_basket_types bt ON bt.id = s.basket_type_id
  WHERE s.opened_at > now() - make_interval(days => GREATEST(COALESCE(p_days, 30), 1))
    AND (
      (p_org_id IS NOT NULL AND s.tenant_id IN (
         SELECT c.tenant_id::text FROM public.churches c WHERE c.organization_id = p_org_id))
      OR (p_org_id IS NULL AND s.tenant_id = COALESCE(p_tenant_id, v_tid))
    )
  GROUP BY s.basket_type_id, COALESCE(s.basket_name, bt.name, 'Offering'), bt.code, bt.tenant_id
  ORDER BY total_amount DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_basket_summary(text, uuid, int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_basket_summary(text, uuid, int) FROM public;
GRANT EXECUTE ON FUNCTION public.get_basket_summary(text, uuid, int) TO authenticated;
