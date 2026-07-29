-- ═══════════════════════════════════════════════════════════════════════════
-- SECURITY: Last-Superadmin Guard + Audit Trigger for Role Changes
-- Prevents demoting the last superadmin at the database level.
-- Also logs role changes to admin_audit_log automatically.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Add last-superadmin guard to the existing check_role_change_permission trigger
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
    -- Check actor has permission
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND (role = 'superadmin' OR role = 'employee')
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

-- 2. Add trigger to automatically log role changes to admin_audit_log
CREATE OR REPLACE FUNCTION public.log_role_change_trigger()
RETURNS TRIGGER
SET search_path = public, auth
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    INSERT INTO public.admin_audit_log (
      admin_id,
      admin_email,
      action,
      entity_type,
      entity_id,
      details
    ) VALUES (
      auth.uid(),
      (SELECT email FROM auth.users WHERE id = auth.uid()),
      'role_change',
      'profile',
      NEW.id,
      jsonb_build_object(
        'old_role', OLD.role,
        'new_role', NEW.role,
        'target_email', NEW.email
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_role_change ON public.profiles;
CREATE TRIGGER trg_log_role_change
  AFTER UPDATE OF role ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.log_role_change_trigger();
