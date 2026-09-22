-- ============================================================================
-- 20261223 — Fix `orders` RLS infinite recursion (42P17)
--
-- ROOT CAUSE (Bug 2): `GET /rest/v1/orders?select=*,order_items(*)` returns
-- HTTP 500. Running the equivalent SQL as a non-owner role reproduces:
--   ERROR: 42P17: infinite recursion detected in policy for relation "orders"
-- Two SELECT policies cross-reference each other through RLS:
--   orders."Vendors can view orders for their items"
--     -> subquery on `order_items` (RLS applied)
--   order_items."Users can view own order items"
--     -> subquery on `orders` (RLS applied)  -> back to the orders policy ...
-- The cycle is never resolvable, so every read of orders (buyer or staff) 500s.
--
-- FIX: move the cross-table lookups into SECURITY DEFINER helpers (which bypass
-- RLS on the tables they read), exactly like the 20261204 bookshop helpers, and
-- recreate the two recursive policies to call them. `is_admin_or_employee()`
-- (already SECURITY DEFINER) replaces the inline `profiles` subqueries.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER — never re-enter the guarded tables' RLS)
-- ---------------------------------------------------------------------------

-- True when the caller placed the order.
CREATE OR REPLACE FUNCTION public.order_belongs_to_caller(p_order uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = p_order AND o.user_id = auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.order_belongs_to_caller(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.order_belongs_to_caller(uuid) TO authenticated;

-- True when the order contains at least one item sold by the caller (vendor).
CREATE OR REPLACE FUNCTION public.order_has_my_vendor_items(p_order uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.order_items oi
    JOIN public.marketplace_items mi ON mi.id = oi.item_id
    WHERE oi.order_id = p_order AND mi.vendor_id = auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.order_has_my_vendor_items(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.order_has_my_vendor_items(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Recreate the two policies that formed the recursion cycle
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Vendors can view orders for their items" ON public.orders;
CREATE POLICY "Vendors can view orders for their items"
  ON public.orders FOR SELECT TO authenticated
  USING (public.order_has_my_vendor_items(id));

DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
CREATE POLICY "Users can view own order items"
  ON public.order_items FOR SELECT TO authenticated
  USING (public.order_belongs_to_caller(order_id));

-- Also drop the inline `profiles` subqueries (same recursion class, and they
-- are the slow path). `is_admin_or_employee()` is SECURITY DEFINER.
DROP POLICY IF EXISTS "Superadmins and employees can view all orders" ON public.orders;
CREATE POLICY "Superadmins and employees can view all orders"
  ON public.orders FOR SELECT TO authenticated
  USING (public.is_admin_or_employee());

DROP POLICY IF EXISTS "Superadmins can view all items" ON public.order_items;
CREATE POLICY "Superadmins can view all items"
  ON public.order_items FOR SELECT TO authenticated
  USING (public.is_admin_or_employee());

-- Verify (informational; deploy output only).
SELECT 'orders recursive policy removed' AS check_name,
       NOT EXISTS (
         SELECT 1 FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'orders'
           AND policyname = 'Vendors can view orders for their items'
           AND qual LIKE '%order_items%'
       ) AS ok;
