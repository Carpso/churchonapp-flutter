-- ═══════════════════════════════════════════════════════════════
-- 20260902: Church registration RLS fix
-- Pastors/bishops could NOT register a church:
--   - tenants INSERT policy only allowed superadmin
--   - churches had NO INSERT policy at all
-- Both failures surfaced as "We encountered a database error"
-- (PostgrestException) with orphaned/unverifiable attempts.
--
-- Fix: authenticated users may register a church:
--   - tenants: INSERT only for type = 'church' (bookshops stay superadmin-only)
--   - churches: INSERT only unverified rows (superadmin approves later;
--     users can NEVER self-verify)
-- ═══════════════════════════════════════════════════════════════

-- 1. Let any authenticated user register a church tenant (not bookshops)
DROP POLICY IF EXISTS "tenants_insert_church_registration" ON public.tenants;
CREATE POLICY "tenants_insert_church_registration"
  ON public.tenants
  FOR INSERT
  TO authenticated
  WITH CHECK (type = 'church');

-- 2. Let users create their church row — always unverified (no self-verify)
DROP POLICY IF EXISTS "churches_insert_registration" ON public.churches;
CREATE POLICY "churches_insert_registration"
  ON public.churches
  FOR INSERT
  TO authenticated
  WITH CHECK (is_verified = false);

-- 3. Users may update the church they registered while it's still unverified
--    (fix a typo in the name/address before the superadmin approves it).
--    profiles.tenant_id is TEXT — compare as text to avoid cast errors on
--    seed tenants (zm_1, zw_2, ...).
DROP POLICY IF EXISTS "churches_update_registration_owner" ON public.churches;
CREATE POLICY "churches_update_registration_owner"
  ON public.churches
  FOR UPDATE
  TO authenticated
  USING (
    is_verified = false
    AND tenant_id::text = (
      SELECT p.tenant_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  )
  WITH CHECK (
    is_verified = false
    AND tenant_id::text = (
      SELECT p.tenant_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );