-- ============================================================================
-- 20261218_fix_profiles_role_trigger.sql
--
-- ROOT CAUSE
--   `trg_profiles_role_change` is defined as `BEFORE UPDATE OF role ON
--   profiles`. A `BEFORE UPDATE OF <col>` trigger fires whenever the UPDATE
--   STATEMENT lists that column — even when the value is unchanged. The
--   self-service tenant switch (`CurrentTenantNotifier.setTenant`) used to send
--   a second `profiles` update carrying `role` (derived from role_assignments),
--   so the trigger fired for a plain tenant switch and raised P0001
--   ("Only superadmins and employees can change roles"). Every switch logged
--   `Error updating profile tenant_id on setTenant` and returned HTTP 400.
--
-- FIX
--   1. The guard must only run when the role VALUE actually changes —
--      `NEW.role IS DISTINCT FROM OLD.role` — so updating tenant_id / name /
--      avatar / phone (or re-sending the same role) can never trip it.
--   2. Recreate the trigger as a plain `BEFORE UPDATE` with a `WHEN (OLD.role
--      IS DISTINCT FROM NEW.role)` clause so it does not even fire for
--      non-role updates.
--   3. Allow `coa_employee` (the current role name) in the actor check — the
--      original only accepted the retired `employee` value.
--
-- The client-side half of the fix (removing `role` from the setTenant update)
-- ships in `lib/core/services/tenant_service.dart`.
--
-- Idempotent: safe to re-run. SECURITY DEFINER + search_path + no anon grant.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_role_change_permission()
RETURNS TRIGGER
SET search_path = public, auth
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  superadmin_count INT;
BEGIN
  -- Only guard an ACTUAL role change. Re-sending the same role, or updating
  -- any other self-service column (tenant_id, full_name, avatar_url,
  -- phone_number, ...), must pass untouched.
  IF NEW.role IS DISTINCT FROM OLD.role THEN

    -- Self-service onboarding roles: a user may apply for these on their own
    -- (pastor/bishop = registering a new church; driver/bookshop_owner/vendor
    -- = onboarding).
    IF NEW.role IN ('driver', 'bookshop_owner', 'vendor', 'pastor', 'bishop')
       AND OLD.id = auth.uid() THEN
      RETURN NEW;
    END IF;

    -- Server-side assignment (Edge Function / service role): allow the
    -- bookshop_owner role only when the new tenant is actually a bookshop.
    IF NEW.role = 'bookshop_owner'
       AND NEW.tenant_id IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.tenants t
         WHERE t.id::text = NEW.tenant_id::text AND t.type = 'bookshop'
       ) THEN
      RETURN NEW;
    END IF;

    -- Actor permission (current role name + legacy alias).
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
    ) THEN
      RAISE EXCEPTION 'Only superadmins and employees can change roles';
    END IF;

    -- Last-superadmin guard: prevent demoting the only superadmin.
    IF OLD.role = 'superadmin' AND NEW.role != 'superadmin' THEN
      SELECT count(*) INTO superadmin_count
      FROM public.profiles
      WHERE role = 'superadmin';
      IF superadmin_count <= 1 THEN
        RAISE EXCEPTION 'Cannot demote the last superadmin. Promote another user first.';
      END IF;
    END IF;

    -- Self-demotion guard: a user cannot change their own role.
    IF OLD.id = auth.uid() THEN
      RAISE EXCEPTION 'You cannot change your own role.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate the trigger so it fires ONLY on a genuine role value change.
DROP TRIGGER IF EXISTS trg_profiles_role_change ON public.profiles;
CREATE TRIGGER trg_profiles_role_change
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  WHEN (OLD.role IS DISTINCT FROM NEW.role)
  EXECUTE FUNCTION public.check_role_change_permission();

-- Two-arg helper used by some RPCs — align its actor check with the rename
-- (superadmin / coa_employee / legacy employee). Idempotent replace.
CREATE OR REPLACE FUNCTION public.check_role_change_permission(target_user_id uuid, new_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'super_admin', 'employee', 'coa_employee')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_role_change_permission() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.check_role_change_permission(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_role_change_permission() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_role_change_permission(uuid, text) TO authenticated, service_role;
