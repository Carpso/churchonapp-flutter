-- 20260931: role approval by coa_employee/staff + profiles visibility for staff
-- Root cause: profiles UPDATE policy is self-only (profiles_update_own), so
-- approving/elevating another user's role (profiles.role write) always got
-- "permission denied" for coa_employee and tenant leaders. Approval is moved
-- into SECURITY DEFINER RPCs with explicit role gates; staff also gain a
-- SELECT policy on profiles so pending-approval lists show real names.

-- Staff (COA/superadmin) can read any profile row. Uses the SECURITY DEFINER
-- is_admin_or_employee() helper (queries auth.users, NOT profiles) to avoid
-- self-referential recursion on the profiles table — a self-referencing
-- EXISTS(SELECT FROM profiles) policy caused Postgres 42P17 "infinite
-- recursion detected in rules for relation profiles" on every profiles read
-- (including live-streaming flows that subquery profiles).
CREATE POLICY profiles_select_staff ON public.profiles
  FOR SELECT TO authenticated
  USING (is_admin_or_employee());

-- Approve/reject a role assignment. Approving propagates the role to
-- profiles.role (bypasses the self-only UPDATE policy — caller is gated).
CREATE OR REPLACE FUNCTION public.approve_role_assignment(p_assignment_id UUID, p_status TEXT DEFAULT 'approved')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_role TEXT;
  v_role_name TEXT;
  v_user_id UUID;
  v_tenant TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller;

  IF v_caller_role NOT IN ('superadmin', 'super_admin', 'employee', 'coa_employee', 'pastor', 'bishop', 'admin') THEN
    RAISE EXCEPTION 'Not authorized to process role assignments';
  END IF;

  SELECT role_name, user_id, tenant_id INTO v_role_name, v_user_id, v_tenant
  FROM public.role_assignments WHERE id = p_assignment_id;
  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'Assignment not found';
  END IF;

  -- Tenant leaders may only process assignments in their own tenant
  IF v_caller_role NOT IN ('superadmin', 'super_admin', 'employee', 'coa_employee') THEN
    IF v_tenant IS NULL OR v_tenant <> (SELECT tenant_id FROM public.profiles WHERE id = v_caller) THEN
      RAISE EXCEPTION 'Cannot process assignments outside your church';
    END IF;
    IF v_role_name IN ('superadmin', 'coa_employee') THEN
      RAISE EXCEPTION 'Only COA management can approve platform-level roles';
    END IF;
  END IF;

  IF p_status = 'approved' THEN
    UPDATE public.role_assignments
    SET status = 'approved', approved_at = now(), rejected_at = NULL, rejection_reason = NULL
    WHERE id = p_assignment_id;
    UPDATE public.profiles SET role = v_role_name WHERE id = v_user_id;
  ELSE
    UPDATE public.role_assignments
    SET status = 'rejected', rejected_at = now()
    WHERE id = p_assignment_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.approve_role_assignment FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_role_assignment TO authenticated;

-- Elevate a user's role immediately (creates an approved assignment +
-- propagates the role). Mirrors the old client-side elevateRole checks.
CREATE OR REPLACE FUNCTION public.elevate_user_role(p_user_id UUID, p_role_name TEXT, p_tenant_id TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_role TEXT;
  v_caller_tenant TEXT;
  v_target_tenant TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT role, tenant_id INTO v_caller_role, v_caller_tenant FROM public.profiles WHERE id = v_caller;
  IF v_caller_role NOT IN ('superadmin', 'super_admin', 'employee', 'coa_employee', 'pastor', 'bishop', 'admin') THEN
    RAISE EXCEPTION 'Not authorized to elevate roles';
  END IF;

  SELECT tenant_id INTO v_target_tenant FROM public.profiles WHERE id = p_user_id;
  IF v_target_tenant IS NULL THEN
    RAISE EXCEPTION 'Target user not found';
  END IF;

  IF v_caller_role NOT IN ('superadmin', 'super_admin', 'employee', 'coa_employee') THEN
    IF v_caller_tenant IS NULL OR v_caller_tenant <> v_target_tenant THEN
      RAISE EXCEPTION 'Cannot elevate users from another tenant';
    END IF;
    IF p_role_name IN ('superadmin', 'coa_employee') THEN
      RAISE EXCEPTION 'Only COA management can assign platform-level roles';
    END IF;
  END IF;

  INSERT INTO public.role_assignments (user_id, role_name, tenant_id, assigned_by, status, approved_at)
  VALUES (p_user_id, p_role_name, COALESCE(p_tenant_id, v_target_tenant), v_caller, 'approved', now());

  UPDATE public.profiles SET role = p_role_name WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.elevate_user_role FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.elevate_user_role TO authenticated;