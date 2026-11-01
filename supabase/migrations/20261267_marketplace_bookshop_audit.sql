-- ============================================================================
-- 20261267 — MARKETPLACE + BOOKSHOP AUDIT FIXES
--
-- 1. DROP test_policy2: a leftover development policy on bookshops with
--    roles={public} that allowed ANYONE to UPDATE any bookshop row.
-- 2. HARDEN decrement_marketplace_stock: the RPC only checked authentication,
--    not vendor ownership — any authenticated user could decrement any
--    item's stock. Now requires the caller to be the vendor who owns the
--    item (or platform staff).
-- 3. Fixed 1 marketplace item ("Bible Hardcover") with an empty image URL.
-- ============================================================================
DROP POLICY IF EXISTS test_policy2 ON public.bookshops;

CREATE OR REPLACE FUNCTION public.decrement_marketplace_stock(p_item_id uuid, p_qty integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock integer;
  v_vendor uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_qty IS NULL OR p_qty <= 0 THEN
    RAISE EXCEPTION 'Invalid quantity';
  END IF;

  -- Only the vendor who owns the item (or platform staff) may decrement.
  SELECT vendor_id INTO v_vendor
    FROM public.marketplace_items
   WHERE id = p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item not found';
  END IF;
  IF v_vendor IS DISTINCT FROM auth.uid()
     AND NOT COALESCE(public.is_platform_staff(), false) THEN
    RAISE EXCEPTION 'Only the vendor can decrement their stock';
  END IF;

  UPDATE public.marketplace_items
     SET stock = GREATEST(0, stock - p_qty)
   WHERE id = p_item_id
  RETURNING stock INTO v_stock;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.decrement_marketplace_stock(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decrement_marketplace_stock(uuid, integer) TO authenticated;