-- 20260919: church_buses RLS — include coa_employee in tenant-bus management
-- (role renamed from employee in 20260848). Same pattern as 20260912/20260917.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Tenant admins can manage buses" ON public.church_buses;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "Tenant admins can manage buses"
ON public.church_buses
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND (p.tenant_id)::uuid = church_buses.tenant_id
      AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'coa_employee', 'employee')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND (p.tenant_id)::uuid = church_buses.tenant_id
      AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'coa_employee', 'employee')
  )
);