-- 1. Redefine is_admin_or_employee to avoid RLS recursion by using JWT app_metadata first,
--    and falling back to auth.users directly. RLS does not apply to auth.users.
CREATE OR REPLACE FUNCTION public.is_admin_or_employee()
RETURNS BOOLEAN
SET search_path = public, auth
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _role TEXT;
BEGIN
  -- Try checking from JWT claims first (very fast)
  _role := (auth.jwt() -> 'app_metadata' ->> 'role');
  IF _role IN ('superadmin', 'employee') THEN
    RETURN TRUE;
  END IF;

  -- Fallback: query auth.users directly (bypasses profiles table RLS)
  SELECT (raw_app_meta_data ->> 'role') INTO _role
  FROM auth.users
  WHERE id = auth.uid();

  RETURN COALESCE(_role, 'member') IN ('superadmin', 'employee');
END;
$$;

-- 2. Drop the recursive policy from public.profiles
DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;

-- 3. Recreate it using our recursion-free SECURITY DEFINER function
CREATE POLICY "Superadmins and employees can manage all profiles" ON public.profiles
  FOR ALL TO authenticated
  USING (public.is_admin_or_employee())
  WITH CHECK (public.is_admin_or_employee());
