-- 20260921: COA EMPLOYEE RLS BATCH + CHURCH REGISTRATION + EXPANSION LEADS PHONE
--
--  1. check_role_change_permission: allow SELF-SERVICE pastor/bishop on church
--     registration (tenant+churches rows already commit; only the profiles role
--     update threw -> "database error" despite the church existing).
--  2. Sync profiles.role -> auth.users.raw_app_meta_data (backfill + trigger) so
--     is_admin_or_employee()/is_super_admin() (20260845, JWT+metadata only) work
--     for profiles-assigned coa_employee/superadmin/employee accounts.
--  3. driver_applications manage: include coa_employee (COA approval flow dead).
--  4. ride_registrations: admins/coa_employee may upsert for others (approval).
--  5. notifications INSERT: allow admin/coa_employee to notify applicants.
--  6. coa_payments SELECT/UPDATE: include coa_employee.
--  7. bookshops SELECT/UPDATE/INSERT: include coa_employee.
--  8. transactions SELECT: include coa_employee (COA dashboard revenue stats).
--  9. expansion_leads: add phone_number column.
-- 10. coins_daily_open_reward 25 -> 1 (daily collect button only).
-- 11. volunteer_schedules INSERT: tenant leaders may schedule volunteers.

-- 1. ROLE-CHANGE TRIGGER: allow self-service pastor/bishop (church registration)
CREATE OR REPLACE FUNCTION public.check_role_change_permission()
RETURNS TRIGGER
SET search_path = public, auth
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  superadmin_count INT;
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    -- Self-service onboarding roles: a user may apply for these on their own
    -- (pastor/bishop = registering a new church; driver/bookshop_owner/vendor = onboarding)
    IF NEW.role IN ('driver', 'bookshop_owner', 'vendor', 'pastor', 'bishop') AND OLD.id = auth.uid() THEN
      RETURN NEW;
    END IF;

    -- Server-side assignment (Edge Function / service role): allow the
    -- bookshop_owner role only when the new tenant is actually a bookshop
    IF NEW.role = 'bookshop_owner' AND NEW.tenant_id IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.tenants t
         WHERE t.id::text = NEW.tenant_id::text AND t.type = 'bookshop'
       ) THEN
      RETURN NEW;
    END IF;

    -- Check actor has permission
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND (role = 'superadmin' OR role = 'employee' OR role = 'coa_employee')
    ) THEN
      RAISE EXCEPTION 'Only superadmins and employees can change roles';
    END IF;

    -- Last-superadmin guard: prevent demoting the only superadmin
    IF OLD.role = 'superadmin' AND NEW.role != 'superadmin' THEN
      SELECT count(*) INTO superadmin_count
      FROM public.profiles
      WHERE role = 'superadmin';

      IF superadmin_count <= 1 THEN
        RAISE EXCEPTION 'Cannot demote the last superadmin. Promote another user first.';
      END IF;
    END IF;

    -- Self-demotion guard: prevent changing your own role
    IF OLD.id = auth.uid() THEN
      RAISE EXCEPTION 'You cannot change your own role.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 2. SYNC profiles.role -> auth.users.raw_app_meta_data
-- (is_admin_or_employee()/is_super_admin() from 20260845 read the JWT claim
--  and auth.users metadata ONLY — profiles-assigned roles never landed there,
--  so every is_super_admin()-gated policy failed for coa_employee accounts.)

-- 2a. Backfill existing privileged profiles
UPDATE auth.users u
SET raw_app_meta_data = COALESCE(u.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', p.role)
FROM public.profiles p
WHERE u.id = p.id
  AND p.role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
  AND COALESCE(u.raw_app_meta_data ->> 'role', '') != p.role;

-- 2b. Keep metadata in sync on every role change
CREATE OR REPLACE FUNCTION public.sync_role_to_auth_metadata()
RETURNS TRIGGER
SET search_path = public, auth
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE auth.users u
  SET raw_app_meta_data = COALESCE(u.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', NEW.role)
  WHERE u.id = NEW.id
    AND NEW.role IN ('superadmin', 'super_admin', 'employee', 'coa_employee');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_role_metadata ON public.profiles;
CREATE TRIGGER trg_sync_role_metadata
  AFTER UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_role_to_auth_metadata();

-- 3. DRIVER APPLICATIONS: coa_employee can view + manage
DO $$ BEGIN
  DROP POLICY IF EXISTS "Admins can manage all driver applications" ON public.driver_applications;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Admins can manage all driver applications" ON public.driver_applications
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee', 'admin', 'pastor', 'bishop'))
  );

-- 4. RIDE REGISTRATIONS: admins/coa_employee may upsert for others (approval flow)
DO $$ BEGIN
  DROP POLICY IF EXISTS "Admins can manage ride registrations" ON public.ride_registrations;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Admins can manage ride registrations" ON public.ride_registrations
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee', 'admin', 'pastor', 'bishop'))
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee', 'admin', 'pastor', 'bishop'))
  );

-- 5. NOTIFICATIONS: admin/coa_employee may insert for other users (approval notices)
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can insert own notifications" ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee', 'admin'))
  );

-- 6. COA PAYMENTS: include coa_employee
DO $$ BEGIN
  DROP POLICY IF EXISTS "coa_payments_select" ON public.coa_payments;
  DROP POLICY IF EXISTS "coa_payments_update" ON public.coa_payments;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "coa_payments_select" ON public.coa_payments FOR SELECT USING (
  auth.uid() = user_id
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee', 'pastor', 'bishop', 'treasurer'))
);
CREATE POLICY "coa_payments_update" ON public.coa_payments FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
);

-- 7. BOOKSHOPS: include coa_employee
DO $$ BEGIN
  DROP POLICY IF EXISTS "bookshops_select" ON public.bookshops;
  DROP POLICY IF EXISTS "bookshops_insert" ON public.bookshops;
  DROP POLICY IF EXISTS "bookshops_update" ON public.bookshops;
  DROP POLICY IF EXISTS "bookshops_delete" ON public.bookshops;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "bookshops_select" ON public.bookshops FOR SELECT USING (
  is_active = true
  OR auth.uid() = owner_id
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee'))
);
CREATE POLICY "bookshops_insert" ON public.bookshops FOR INSERT WITH CHECK (
  auth.uid() = owner_id
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee'))
);
CREATE POLICY "bookshops_update" ON public.bookshops FOR UPDATE USING (
  auth.uid() = owner_id
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee'))
);
CREATE POLICY "bookshops_delete" ON public.bookshops FOR DELETE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee'))
);

-- 8. TRANSACTIONS: include coa_employee for leader view + full manage
DO $$ BEGIN
  DROP POLICY IF EXISTS "Leaders can view church transactions" ON public.transactions;
  DROP POLICY IF EXISTS "Superadmins can manage all transactions" ON public.transactions;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Leaders can view church transactions" ON public.transactions
  FOR SELECT TO authenticated USING (
    tenant_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.tenant_id::text = transactions.tenant_id::text
        AND p.role IN ('admin', 'pastor', 'bishop', 'general_treasurer', 'general_secretary', 'superadmin', 'employee', 'coa_employee')
    )
  );
CREATE POLICY "Superadmins can manage all transactions" ON public.transactions
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee', 'coa_employee'))
  );

-- 9. EXPANSION LEADS: phone number column
ALTER TABLE public.expansion_leads ADD COLUMN IF NOT EXISTS phone_number TEXT;

-- 10. DAILY COINS: 25 -> 1 (collect button is the only daily path)
INSERT INTO public.platform_settings (key, value)
VALUES ('coins_daily_open_reward', '1')
ON CONFLICT (key) DO UPDATE SET value = '1';

-- 11. VOLUNTEER SCHEDULES: tenant leaders may schedule volunteers
DO $$ BEGIN
  DROP POLICY IF EXISTS "volunteer_schedules_insert" ON public.volunteer_schedules;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "volunteer_schedules_insert" ON public.volunteer_schedules FOR INSERT WITH CHECK (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (role IN ('superadmin', 'employee', 'coa_employee') OR role IN ('admin', 'pastor', 'bishop') AND tenant_id::text = volunteer_schedules.tenant_id::text)
  )
);
