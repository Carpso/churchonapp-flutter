-- ═══════════════════════════════════════════════════════════════
-- 20260903: Year Planner RLS + visibility fix
-- Problems:
--  1. Legacy "Anyone can view year planner" (USING true) leaked ALL
--     year_planner rows (every tenant) to every authenticated user.
--  2. Legacy "Tenant admins can manage events" cast profiles.tenant_id
--     to uuid — errors for seed tenants (zm_1, zw_2) and only allowed
--     5 roles.
--  3. Same-church members saw "No annual programs planned yet" because
--     no SELECT policy covered non-admin tenants.
--  4. Manage role list didn't match app isAdminOrHigher (prophet, apostle,
--     bishop, general_secretary, leader, general_treasurer got the +
--     button but their INSERT was denied by RLS).
-- ═══════════════════════════════════════════════════════════════

-- 0. Drop the legacy leaky/invalid policies (superseded below)
DROP POLICY IF EXISTS "Anyone can view year planner" ON public.year_planner;
DROP POLICY IF EXISTS "Tenant admins can manage events" ON public.year_planner;

-- 1. Personal planner items: ONLY the owner (no more user_id IS NULL leak)
DROP POLICY IF EXISTS "Users can manage own planner items" ON public.year_planner;
CREATE POLICY "Users can manage own planner items"
  ON public.year_planner
  FOR ALL
  TO authenticated
  USING (auth.uid()::text = user_id::text)
  WITH CHECK (auth.uid()::text = user_id::text);

-- 2. Same-church members may VIEW the church's annual programs
--    (get_my_tenant_id is SECURITY DEFINER — no RLS recursion)
DROP POLICY IF EXISTS "Tenants can view planner items" ON public.year_planner;
CREATE POLICY "Tenants can view planner items"
  ON public.year_planner
  FOR SELECT
  TO authenticated
  USING (tenant_id::text = public.get_my_tenant_id());

-- 3. Leadership manages tenant programs (role list matches isAdminOrHigher)
DROP POLICY IF EXISTS "Tenants can manage tenant planner items" ON public.year_planner;
CREATE POLICY "Tenants can manage tenant planner items"
  ON public.year_planner
  FOR ALL
  TO authenticated
  USING (
    tenant_id IS NOT NULL
    AND tenant_id::text = public.get_my_tenant_id()
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('admin', 'superadmin', 'employee', 'coa_employee', 'pastor',
                     'bishop', 'apostle', 'prophet', 'general_secretary',
                     'leader', 'department_leader', 'general_treasurer')
    )
  );