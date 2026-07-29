-- Fix tenants table INSERT RLS policy
-- The old policies only allowed superadmins to insert, but church registration
-- requires any authenticated user to create a tenant

DROP POLICY IF EXISTS tenants_insert ON public.tenants;
DROP POLICY IF EXISTS "tenants_insert" ON public.tenants;

CREATE POLICY tenants_insert ON public.tenants FOR INSERT WITH CHECK (
  auth.role() = 'authenticated'
);

DROP POLICY IF EXISTS tenants_update ON public.tenants;
DROP POLICY IF EXISTS "tenants_update" ON public.tenants;

CREATE POLICY tenants_update ON public.tenants FOR UPDATE USING (
  auth.jwt() -> 'app_metadata' ->> 'role' IN ('superadmin', 'super_admin')
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
);
