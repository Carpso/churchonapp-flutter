-- ============================================================================
-- 20261137_offering_baskets.sql
-- Offering basket types + live basket offering sessions + reporting.
--
-- WHY: churches take several kinds of offering (Tithe, Sunday Offering,
-- Missions, Building Fund, Welfare, First Fruits…). There was no way for a
-- tenant leader to define their own basket types, so the Give tab could not
-- reflect them, admin management could not list them, and pastors/bishops had
-- nothing to report on.
--
-- SCOPE (per product decision):
--   * TENANT baskets    -> tenant_id set (+ organization_id for rollup)
--   * ORGANISATION baskets -> organization_id set, tenant_id NULL, visible to
--     every church inside that organisation.
--   A basket may carry an accounting/GL `code` for bookkeeping.
--
-- A LIVE BASKET OFFERING is a timed session a leader opens ("offering time"):
--   open_offering_session() → members give into that basket → close_offering_session()
--   → totals roll up into `get_basket_summary()`.
-- ============================================================================

-- ── 1. Basket types ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.offering_basket_types (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       text,                       -- NULL = organisation-wide basket
  organization_id uuid,                       -- rollup scope
  name            text NOT NULL,
  code            text,                       -- accounting / GL code
  description     text,
  icon            text DEFAULT 'hand-heart',
  color           text DEFAULT '#FFDA03',
  is_active       boolean NOT NULL DEFAULT true,
  sort_order      int NOT NULL DEFAULT 0,
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_basket_types_tenant
  ON public.offering_basket_types (tenant_id, is_active, sort_order);
CREATE INDEX IF NOT EXISTS idx_basket_types_org
  ON public.offering_basket_types (organization_id, is_active);

ALTER TABLE public.offering_basket_types ENABLE ROW LEVEL SECURITY;

-- Read: your church's baskets + your organisation's baskets (+ staff).
DROP POLICY IF EXISTS "basket_types_read" ON public.offering_basket_types;
CREATE POLICY "basket_types_read"
  ON public.offering_basket_types FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR (
      tenant_id IS NULL
      AND organization_id IS NOT NULL
      AND organization_id = (
        SELECT c.organization_id FROM public.churches c
        WHERE c.tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
        LIMIT 1
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- ── 2. Live offering sessions ("offering time") ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.offering_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       text NOT NULL,
  basket_type_id  uuid REFERENCES public.offering_basket_types(id) ON DELETE SET NULL,
  basket_name     text,                       -- snapshot (survives basket edits)
  title           text,
  status          text NOT NULL DEFAULT 'open',   -- open | closed
  opened_by       uuid,
  opened_at       timestamptz NOT NULL DEFAULT now(),
  closed_at       timestamptz,
  total_amount    numeric NOT NULL DEFAULT 0,
  contribution_count int NOT NULL DEFAULT 0,
  notes           text
);

CREATE INDEX IF NOT EXISTS idx_offering_sessions_tenant
  ON public.offering_sessions (tenant_id, opened_at DESC);

ALTER TABLE public.offering_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "offering_sessions_tenant_read" ON public.offering_sessions;
CREATE POLICY "offering_sessions_tenant_read"
  ON public.offering_sessions FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );
-- Writes only via the RPCs below.

-- ── 3. Create / update a basket type ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_offering_basket(
  p_name        text,
  p_code        text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_icon        text DEFAULT 'hand-heart',
  p_color       text DEFAULT '#FFDA03',
  p_sort_order  int  DEFAULT 0,
  p_org_wide    boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_role text;
  v_org  uuid;
  v_id   uuid;
  v_perm boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'no tenant'; END IF;

  -- Leadership may manage baskets: owner tier, or an admin-style role.
  v_perm := public.is_owner_tier_role(v_role)
            OR lower(coalesce(v_role, '')) IN
               ('superadmin', 'super_admin', 'coa_employee', 'employee',
                'admin', 'leader', 'department_leader');
  IF NOT v_perm THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT organization_id INTO v_org FROM public.churches
   WHERE tenant_id::text = v_tid LIMIT 1;

  -- Organisation-wide baskets may only be created by an ORGANISATION owner.
  IF p_org_wide AND lower(coalesce(v_role, '')) NOT IN
     ('bishop', 'apostle', 'prophet', 'general_secretary', 'general_treasurer',
      'superadmin', 'super_admin', 'coa_employee', 'employee') THEN
    RAISE EXCEPTION 'org_owner_required';
  END IF;

  INSERT INTO public.offering_basket_types
    (tenant_id, organization_id, name, code, description, icon, color,
     sort_order, created_by)
  VALUES
    (CASE WHEN p_org_wide THEN NULL ELSE v_tid END, v_org,
     p_name, p_code, p_description, p_icon, p_color, p_sort_order, v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('basket_id', v_id, 'org_wide', p_org_wide);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_offering_basket(text, text, text, text, text, int, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_offering_basket(text, text, text, text, text, int, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.create_offering_basket(text, text, text, text, text, int, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_offering_basket(
  p_basket_id uuid,
  p_name      text DEFAULT NULL,
  p_code      text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL,
  p_sort_order int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_role text;
  v_own text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;
  SELECT tenant_id INTO v_own FROM public.offering_basket_types WHERE id = p_basket_id;
  IF v_own IS NULL THEN RAISE EXCEPTION 'basket_not_found'; END IF;

  IF NOT (v_own = v_tid AND (
            public.is_owner_tier_role(v_role)
            OR lower(coalesce(v_role, '')) IN ('admin', 'leader', 'department_leader')))
     AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_uid
                      AND p.role IN ('superadmin','super_admin','coa_employee','employee'))
     AND NOT (v_own IS NULL AND lower(coalesce(v_role,'')) IN
              ('bishop','apostle','prophet','general_secretary','general_treasurer')) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  UPDATE public.offering_basket_types
     SET name = COALESCE(p_name, name),
         code = COALESCE(p_code, code),
         is_active = COALESCE(p_is_active, is_active),
         sort_order = COALESCE(p_sort_order, sort_order)
   WHERE id = p_basket_id;

  RETURN jsonb_build_object('updated', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_offering_basket(uuid, text, text, boolean, int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_offering_basket(uuid, text, text, boolean, int) FROM public;
GRANT EXECUTE ON FUNCTION public.update_offering_basket(uuid, text, text, boolean, int) TO authenticated;

-- ── 4. Open / close a LIVE basket offering ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.open_offering_session(
  p_basket_type_id uuid,
  p_title          text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_tid  text;
  v_role text;
  v_name text;
  v_id   uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'no tenant'; END IF;

  IF NOT (public.is_owner_tier_role(v_role)
          OR lower(coalesce(v_role, '')) IN
             ('superadmin','super_admin','coa_employee','employee',
              'admin','leader','department_leader')) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT name INTO v_name FROM public.offering_basket_types WHERE id = p_basket_type_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'basket_not_found'; END IF;

  -- Only one live offering per church at a time.
  UPDATE public.offering_sessions
     SET status = 'closed', closed_at = now()
   WHERE tenant_id = v_tid AND status = 'open';

  INSERT INTO public.offering_sessions
    (tenant_id, basket_type_id, basket_name, title, status, opened_by)
  VALUES (v_tid, p_basket_type_id, v_name, p_title, 'open', v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('session_id', v_id, 'basket', v_name);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.open_offering_session(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.open_offering_session(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.open_offering_session(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_offering_session(
  p_session_id uuid,
  p_notes      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
  v_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;

  IF NOT (public.is_owner_tier_role(v_role)
          OR lower(coalesce(v_role, '')) IN
             ('superadmin','super_admin','coa_employee','employee',
              'admin','leader','department_leader')) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  UPDATE public.offering_sessions
     SET status = 'closed', closed_at = now(),
         notes = COALESCE(p_notes, notes)
   WHERE id = p_session_id AND tenant_id = v_tid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('closed', false, 'reason', 'not_found');
  END IF;

  RETURN jsonb_build_object('closed', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_offering_session(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.close_offering_session(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.close_offering_session(uuid, text) TO authenticated;

-- ── 5. Reporting: basket summary for a church OR a whole organisation ───────
CREATE OR REPLACE FUNCTION public.get_basket_summary(
  p_tenant_id text DEFAULT NULL,
  p_org_id    uuid DEFAULT NULL,
  p_days      int  DEFAULT 30
)
RETURNS TABLE (
  basket_type_id uuid,
  basket_name    text,
  basket_code    text,
  scope          text,          -- tenant | organisation
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
  v_org  uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;

  -- Church leaders may only report on their own church. Organisation leaders
  -- (bishop & co) and platform staff may roll up an organisation.
  IF p_org_id IS NOT NULL THEN
    IF lower(coalesce(v_role, '')) NOT IN
       ('bishop','apostle','prophet','general_secretary','general_treasurer',
        'superadmin','super_admin','coa_employee','employee') THEN
      RAISE EXCEPTION 'not_authorised';
    END IF;
    SELECT organization_id INTO v_org FROM public.churches
     WHERE tenant_id::text = v_tid LIMIT 1;
    IF v_org IS NULL OR v_org <> p_org_id THEN
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

-- ── 6. Seed the common Zambian church baskets for every tenant ──────────────
INSERT INTO public.offering_basket_types (tenant_id, name, code, description, icon, sort_order)
SELECT c.tenant_id::text, b.name, b.code, b.descr, b.icon, b.sort_order
FROM public.churches c
CROSS JOIN (VALUES
  ('Tithe',             'TITHE', 'Regular tithe',                  'hand-heart', 1),
  ('Sunday Offering',   'SUN',   'Weekly Sunday service offering', 'church',     2),
  ('Missions',          'MIS',   'Missions and outreach',          'globe',      3),
  ('Building Fund',     'BLD',   'Building and construction',      'building-2', 4),
  ('Welfare',           'WEL',   'Welfare and benevolence',        'heart-handshake', 5),
  ('First Fruits',      'FF',    'First fruits offering',          'sprout',     6)
) AS b(name, code, descr, icon, sort_order)
WHERE c.tenant_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.offering_basket_types x
    WHERE x.tenant_id = c.tenant_id::text AND x.name = b.name
  );
