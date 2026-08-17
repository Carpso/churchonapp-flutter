-- ============================================================
-- 20260912_fix_role_assignments_rls_coa.sql
-- Fix: migration 20260848 renamed the 'employee' role to
-- 'coa_employee' in profiles + role_assignments data, but the
-- role_assignments RLS policies (20260709, 20260840) still gate
-- on role IN ('superadmin','employee',...) — so COA employees
-- were blocked from SELECT/INSERT/UPDATE on role_assignments
-- and the entire COA-team role-assignment flow failed
-- server-side ("permission denied") for them.
-- ============================================================

-- 1. Recreate the 20260709 FOR ALL manage policy (was: superadmin/employee only)
DO $$ BEGIN
  DROP POLICY IF EXISTS "Superadmins/employees can manage all assignments" ON public.role_assignments;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Superadmins/employees can manage all assignments"
  ON public.role_assignments
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
    )
  );

-- 2. Extend the tenant-lead view policy with COA staff
DO $$ BEGIN
  DROP POLICY IF EXISTS "Main role leads can view assignments in own tenant" ON public.role_assignments;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Main role leads can view assignments in own tenant"
  ON public.role_assignments
  FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee',
                     'bishop', 'pastor', 'bookshop_owner', 'prophet', 'apostle', 'admin')
    )
  );

-- 3. Recreate the 20260840 SELECT policy (coa_employee was missing)
DO $$ BEGIN
  DROP POLICY IF EXISTS "role_assignments_select" ON public.role_assignments;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "role_assignments_select"
  ON public.role_assignments
  FOR SELECT
  USING (
    auth.uid() = user_id OR
    auth.uid() = assigned_by OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
    )
  );

-- 4. Recreate the 20260840 INSERT policy (coa_employee was missing)
DO $$ BEGIN
  DROP POLICY IF EXISTS "role_assignments_insert" ON public.role_assignments;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "role_assignments_insert"
  ON public.role_assignments
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee', 'pastor', 'bishop')
    )
  );

-- 5. Recreate the 20260840 UPDATE policy (coa_employee was missing)
DO $$ BEGIN
  DROP POLICY IF EXISTS "role_assignments_update" ON public.role_assignments;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "role_assignments_update"
  ON public.role_assignments
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
    )
  );
