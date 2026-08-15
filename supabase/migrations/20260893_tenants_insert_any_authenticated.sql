-- Registration flow: any authenticated user may create a tenant row for their
-- own church (mirrors the existing "Authenticated users can create churches"
-- policy). Superadmin-only enforcement was blocking church registration with
-- a generic "try again later" error because the flow inserts into tenants first.

DROP POLICY IF EXISTS tenants_insert ON tenants;

CREATE POLICY tenants_insert ON tenants
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Superadmins keep full control via the existing SELECT/UPDATE/DELETE policies.