-- 20261219_fix_resolution_hub.sql
-- Resolution Hub hardening (support tickets, disputes, COA error reports).
--
-- Root cause fixed here: the SELECT/UPDATE policies created in 20260887 gated
-- staff access on a hardcoded role list ('superadmin', 'employee',
-- 'coa_employee'). That list is (a) missing the 'super_admin' alias and (b)
-- duplicated in three places, so any role-set change silently locked COA staff
-- out of resolving tickets/disputes/error reports. All staff checks now go
-- through the single source of truth `public.is_platform_staff()`
-- (superadmin, super_admin, coa_employee, legacy employee).
--
-- Owners keep full read on their own rows. Error-report responses stay
-- staff-only (a reporter must not be able to edit the resolution trail).
-- No policy ever grants anon, and no policy uses WITH CHECK (true).

-- ── support_tickets ────────────────────────────────────────────────
DROP POLICY IF EXISTS "support_tickets_select" ON public.support_tickets;
CREATE POLICY "support_tickets_select" ON public.support_tickets
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_platform_staff());

DROP POLICY IF EXISTS "support_tickets_insert" ON public.support_tickets;
CREATE POLICY "support_tickets_insert" ON public.support_tickets
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "support_tickets_update" ON public.support_tickets;
CREATE POLICY "support_tickets_update" ON public.support_tickets
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id OR public.is_platform_staff())
  WITH CHECK (auth.uid() = user_id OR public.is_platform_staff());

-- ── support_disputes ───────────────────────────────────────────────
DROP POLICY IF EXISTS "support_disputes_select" ON public.support_disputes;
CREATE POLICY "support_disputes_select" ON public.support_disputes
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_platform_staff());

DROP POLICY IF EXISTS "support_disputes_insert" ON public.support_disputes;
CREATE POLICY "support_disputes_insert" ON public.support_disputes
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "support_disputes_update" ON public.support_disputes;
CREATE POLICY "support_disputes_update" ON public.support_disputes
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id OR public.is_platform_staff())
  WITH CHECK (auth.uid() = user_id OR public.is_platform_staff());

-- ── app_error_reports ─────────────────────────────────────────────
DROP POLICY IF EXISTS "app_error_reports_select" ON public.app_error_reports;
CREATE POLICY "app_error_reports_select" ON public.app_error_reports
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_platform_staff());

DROP POLICY IF EXISTS "app_error_reports_insert" ON public.app_error_reports;
CREATE POLICY "app_error_reports_insert" ON public.app_error_reports
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "app_error_reports_update" ON public.app_error_reports;
CREATE POLICY "app_error_reports_update" ON public.app_error_reports
  FOR UPDATE TO authenticated
  USING (public.is_platform_staff())
  WITH CHECK (public.is_platform_staff());

-- Staff need to sort/scan the triage queues quickly.
CREATE INDEX IF NOT EXISTS idx_support_tickets_status_created
  ON public.support_tickets(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_disputes_status_created
  ON public.support_disputes(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_error_reports_status_created
  ON public.app_error_reports(status, created_at DESC);
