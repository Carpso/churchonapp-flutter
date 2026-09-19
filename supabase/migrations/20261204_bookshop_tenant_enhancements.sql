ALTER TABLE public.bookshops ADD COLUMN IF NOT EXISTS show_in_marketplace boolean NOT NULL DEFAULT false;

-- ============================================================================
-- 20261204 â€” BOOKSHOP TENANT ENHANCEMENTS
--
-- 1. Fix orders 42P17 (infinite recursion in RLS) for bookshop staff.
--    Root cause: the staff policies on `orders`/`order_items` used inline
--    subqueries on `profiles`, and `profiles_select_same_tenant` calls
--    `get_my_tenant_id()` which reads `profiles` again -> the policy graph
--    re-enters itself (42P17). Replaced with SECURITY DEFINER helpers so the
--    guarded tables are never re-queried through RLS.
-- 2. Cross-list opted-in bookshop products into church marketplaces.
-- 3. Order status state machine + timestamps + sales summary.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. SECURITY DEFINER helpers (no inline subquery on a guarded table)
-- ---------------------------------------------------------------------------

-- True when the caller is platform staff OR a staff member of p_tenant.
CREATE OR REPLACE FUNCTION public.is_bookshop_staff(p_tenant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_admin_or_employee()
      OR EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role IN ('bookshop_owner', 'store_manager', 'assistant', 'cashier')
          AND p.tenant_id IS NOT NULL
          AND (p_tenant IS NULL OR p.tenant_id::text = p_tenant::text)
      );
$$;

REVOKE EXECUTE ON FUNCTION public.is_bookshop_staff(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_bookshop_staff(uuid) TO authenticated;

-- Staff-or-buyer view of one order (used by the order_items policy) without
-- re-entering the orders RLS policy.
CREATE OR REPLACE FUNCTION public.bookshop_can_view_order(p_order uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT (o.user_id = auth.uid() OR public.is_bookshop_staff(o.tenant_id))
    FROM public.orders o
    WHERE o.id = p_order
  ), false);
$$;

REVOKE EXECUTE ON FUNCTION public.bookshop_can_view_order(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.bookshop_can_view_order(uuid) TO authenticated;

-- True when p_tenant belongs to a bookshop.
CREATE OR REPLACE FUNCTION public.is_bookshop_tenant(p_tenant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookshops b WHERE b.tenant_id = p_tenant
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_bookshop_tenant(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_bookshop_tenant(uuid) TO authenticated;

-- True when a bookshop has opted its catalogue into church marketplaces.
CREATE OR REPLACE FUNCTION public.bookshop_is_public_listed(p_tenant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookshops b
    WHERE b.tenant_id = p_tenant AND b.show_in_marketplace = true
  );
$$;

REVOKE EXECUTE ON FUNCTION public.bookshop_is_public_listed(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.bookshop_is_public_listed(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 1b. Replace the recursive orders / order_items staff policies
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Bookshop staff can view tenant orders" ON public.orders;
CREATE POLICY "Bookshop staff can view tenant orders"
  ON public.orders FOR SELECT TO authenticated
  USING (public.is_bookshop_staff(tenant_id));

DROP POLICY IF EXISTS "Bookshop staff can view tenant order items" ON public.order_items;
CREATE POLICY "Bookshop staff can view tenant order items"
  ON public.order_items FOR SELECT TO authenticated
  USING (public.bookshop_can_view_order(order_id));

-- ---------------------------------------------------------------------------
-- 2. Bookshop cross-listing into church marketplaces
-- ---------------------------------------------------------------------------

ALTER TABLE public.bookshops
  ADD COLUMN IF NOT EXISTS show_in_marketplace boolean NOT NULL DEFAULT false;

-- Shop staff can flip their own catalogue's cross-listing setting.
DROP POLICY IF EXISTS "Bookshop staff can update their shop" ON public.bookshops;
CREATE POLICY "Bookshop staff can update their shop"
  ON public.bookshops FOR UPDATE TO authenticated
  USING (public.is_bookshop_staff(tenant_id))
  WITH CHECK (public.is_bookshop_staff(tenant_id));

-- Opted-in bookshop tenant ids. SECURITY DEFINER so church members can build
-- the cross-listing query without being blocked by `bookshops_select` RLS.
CREATE OR REPLACE FUNCTION public.get_marketplace_bookshop_tenants()
RETURNS TABLE(tenant_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.tenant_id
  FROM public.bookshops b
  WHERE b.show_in_marketplace = true
    AND b.tenant_id IS NOT NULL;
$$;

REVOKE EXECUTE ON FUNCTION public.get_marketplace_bookshop_tenants() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_marketplace_bookshop_tenants() TO authenticated;

-- Church members may only read a bookshop's catalogue when the shop opted in,
-- when it is their own tenant, or when they are staff. Non-bookshop sellers
-- stay globally visible (unchanged). No recursion: helpers are SECURITY DEFINER.
DROP POLICY IF EXISTS "Anyone can view marketplace items" ON public.marketplace_items;
DROP POLICY IF EXISTS "marketplace_items_select_visible" ON public.marketplace_items;

CREATE POLICY "marketplace_items_select_visible"
  ON public.marketplace_items FOR SELECT TO authenticated
  USING (
    status = 'active'
    AND (
      tenant_id IS NULL
      OR public.is_bookshop_staff(tenant_id)
      OR public.get_my_tenant_id() = tenant_id::text
      OR NOT public.is_bookshop_tenant(tenant_id)
      OR public.bookshop_is_public_listed(tenant_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Order status state machine + timestamps + sales summary
-- ---------------------------------------------------------------------------

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS confirmed_at  timestamptz,
  ADD COLUMN IF NOT EXISTS processing_at timestamptz,
  ADD COLUMN IF NOT EXISTS shipped_at    timestamptz,
  ADD COLUMN IF NOT EXISTS delivered_at  timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at  timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at   timestamptz;

-- Stamp the transition timestamp whenever the status changes.
CREATE OR REPLACE FUNCTION public.stamp_order_status_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.updated_at := now();
    IF NEW.status = 'confirmed'  THEN NEW.confirmed_at  := COALESCE(NEW.confirmed_at,  now());
    ELSIF NEW.status = 'processing' THEN NEW.processing_at := COALESCE(NEW.processing_at, now());
    ELSIF NEW.status = 'shipped'    THEN NEW.shipped_at    := COALESCE(NEW.shipped_at,    now());
    ELSIF NEW.status = 'delivered'  THEN NEW.delivered_at  := COALESCE(NEW.delivered_at,  now());
    ELSIF NEW.status = 'cancelled'  THEN NEW.cancelled_at  := COALESCE(NEW.cancelled_at,  now());
    ELSIF NEW.status = 'refunded'   THEN NEW.refunded_at   := COALESCE(NEW.refunded_at,   now());
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_order_status ON public.orders;
CREATE TRIGGER trg_stamp_order_status
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.stamp_order_status_timestamp();

-- Validate + apply a transition. Buyers may only cancel before shipping.
CREATE OR REPLACE FUNCTION public.set_order_status(p_order_id uuid, p_status text)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_uid   uuid := auth.uid();
  v_staff boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_staff := public.is_bookshop_staff(v_order.tenant_id);

  IF NOT (v_staff OR public.is_admin_or_employee() OR v_order.user_id = v_uid) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Buyer (not staff) may only cancel, and only before it ships.
  IF v_order.user_id = v_uid AND NOT v_staff AND NOT public.is_admin_or_employee() THEN
    IF p_status <> 'cancelled'
       OR v_order.status NOT IN ('pending', 'confirmed', 'processing') THEN
      RAISE EXCEPTION 'Buyers may only cancel an order before it is shipped';
    END IF;
  END IF;

  IF p_status IS DISTINCT FROM v_order.status THEN
    IF NOT (
      (v_order.status = 'pending'    AND p_status IN ('confirmed', 'cancelled')) OR
      (v_order.status = 'confirmed'  AND p_status IN ('processing', 'cancelled')) OR
      (v_order.status = 'processing' AND p_status IN ('shipped', 'cancelled')) OR
      (v_order.status = 'shipped'    AND p_status = 'delivered') OR
      (v_order.status = 'delivered'  AND p_status = 'refunded')
    ) THEN
      RAISE EXCEPTION 'Invalid status transition: % -> %', v_order.status, p_status;
    END IF;
  END IF;

  UPDATE public.orders SET status = p_status WHERE id = p_order_id RETURNING * INTO v_order;
  RETURN v_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_order_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_order_status(uuid, text) TO authenticated;

-- Real, range-scoped sales summary (order count, revenue, units, AOV).
CREATE OR REPLACE FUNCTION public.get_bookshop_sales_summary(
  p_tenant uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  IF NOT (public.is_admin_or_employee() OR public.is_bookshop_staff(p_tenant)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT jsonb_build_object(
    'order_count', COALESCE(COUNT(o.id), 0),
    'revenue', COALESCE(SUM(o.total_amount) FILTER (
        WHERE o.status NOT IN ('pending', 'cancelled', 'refunded')), 0),
    'avg_order_value', COALESCE(AVG(o.total_amount) FILTER (
        WHERE o.status NOT IN ('pending', 'cancelled', 'refunded')), 0),
    'units_sold', COALESCE((
        SELECT SUM(oi.quantity)
        FROM public.order_items oi
        JOIN public.orders o2 ON o2.id = oi.order_id
        WHERE o2.tenant_id = p_tenant
          AND o2.status NOT IN ('pending', 'cancelled', 'refunded')
          AND o2.created_at >= p_from AND o2.created_at < p_to
    ), 0)
  ) INTO v
  FROM public.orders o
  WHERE o.tenant_id = p_tenant
    AND o.created_at >= p_from
    AND o.created_at < p_to;

  RETURN v;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_bookshop_sales_summary(uuid, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_bookshop_sales_summary(uuid, timestamptz, timestamptz) TO authenticated;

-- Real customers of a shop: unique buyers with names (reads profiles in a
-- SECURITY DEFINER context so cross-tenant buyer rows are not RLS-blocked).
CREATE OR REPLACE FUNCTION public.get_bookshop_customers(p_tenant uuid)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text,
  role text,
  order_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (public.is_admin_or_employee() OR public.is_bookshop_staff(p_tenant)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT o.user_id,
         COALESCE(p.full_name, '')::text,
         COALESCE(p.email, '')::text,
         COALESCE(p.role, 'member')::text,
         COUNT(*)::bigint
  FROM public.orders o
  LEFT JOIN public.profiles p ON p.id = o.user_id
  WHERE o.tenant_id = p_tenant
  GROUP BY o.user_id, p.full_name, p.email, p.role
  ORDER BY COUNT(*) DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_bookshop_customers(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_bookshop_customers(uuid) TO authenticated;

-- Verify
SELECT 'orders staff policy helper' AS check_name, to_regprocedure('public.is_bookshop_staff(uuid)') IS NOT NULL AS ok
UNION ALL
SELECT 'bookshops.show_in_marketplace', EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'bookshops'
    AND column_name = 'show_in_marketplace'
);
