-- Fix tenants table RLS policies
-- The old policies used `?` (key existence) instead of `->>` (value extraction)
-- This caused 42501 "new row violates row-level security policy" on inserts

DROP POLICY IF EXISTS tenants_insert ON public.tenants;
CREATE POLICY tenants_insert ON public.tenants FOR INSERT WITH CHECK (
  (auth.jwt() -> 'app_metadata' ->> 'role') = 'superadmin'
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'superadmin')
);

DROP POLICY IF EXISTS tenants_update ON public.tenants;
CREATE POLICY tenants_update ON public.tenants FOR UPDATE USING (
  (auth.jwt() -> 'app_metadata' ->> 'role') = 'superadmin'
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'superadmin')
);
