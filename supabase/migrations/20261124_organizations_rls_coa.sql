-- Branch management: COA staff must be able to manage churches + organisations.
--
-- The 20260848 role rename (`employee` -> `coa_employee`) left these policies
-- gating on the legacy `employee` role only, so COA (who onboard churches and
-- own branch linking) could NOT create/attach branches. Bishops could already
-- READ their organisation's branches ("Bishops can view organization churches"),
-- but nobody could WRITE `churches.organization_id`.

DROP POLICY IF EXISTS "Superadmins can manage churches" ON public.churches;
CREATE POLICY "Superadmins can manage churches" ON public.churches
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ));

DROP POLICY IF EXISTS "Superadmins can update churches" ON public.churches;
CREATE POLICY "Superadmins can update churches" ON public.churches
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ));

DROP POLICY IF EXISTS "Superadmins can manage organizations" ON public.organizations;
CREATE POLICY "Superadmins can manage organizations" ON public.organizations
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  ));
