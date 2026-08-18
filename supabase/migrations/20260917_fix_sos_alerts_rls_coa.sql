-- 20260917: SOS alerts RLS — include coa_employee (renamed from employee in 20260848).
-- Previously only superadmin/employee could view/manage alerts, so COA staff
-- got "permission denied" in the Emergency SOS Manager.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Superadmins can view and manage SOS alerts" ON public.sos_alerts;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "Superadmins and COA can view and manage SOS alerts"
ON public.sos_alerts
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'coa_employee', 'employee', 'super_admin')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'coa_employee', 'employee', 'super_admin')
  )
);

-- Users can still create their own SOS alerts (unchanged).
DROP POLICY IF EXISTS "Users can create SOS alerts" ON public.sos_alerts;
CREATE POLICY "Users can create SOS alerts"
ON public.sos_alerts
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);