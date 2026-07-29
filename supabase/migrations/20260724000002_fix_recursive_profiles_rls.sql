-- 1. Sync existing profiles' roles to auth.users raw_app_meta_data
UPDATE auth.users u
SET raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', p.role)
FROM public.profiles p
WHERE u.id = p.id;

-- 2. Trigger function to sync profile role changes to auth.users app_metadata
CREATE OR REPLACE FUNCTION public.sync_profile_role_to_app_metadata()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', NEW.role)
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Attach trigger to public.profiles
DROP TRIGGER IF EXISTS trg_sync_profile_role_to_app_metadata ON public.profiles;
CREATE TRIGGER trg_sync_profile_role_to_app_metadata
  AFTER INSERT OR UPDATE OF role ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_profile_role_to_app_metadata();

-- 4. Re-define handle_new_user to set the default 'member' role in raw_app_meta_data
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SET search_path = public, auth
AS $$
BEGIN
  -- Update raw_app_meta_data of the new user to have role 'member'
  UPDATE auth.users
  SET raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'member')
  WHERE id = new.id;

  INSERT INTO public.profiles (id, full_name, role, coins, is_work_mode, avatar_url, tenant_id)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Believer'),
    'member',
    500,
    false,
    COALESCE(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    NULL
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Re-define is_admin_or_employee to bypass RLS by querying auth.users instead of profiles
CREATE OR REPLACE FUNCTION public.is_admin_or_employee()
RETURNS BOOLEAN
SET search_path = public, auth
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _role TEXT;
BEGIN
  -- Try checking from JWT first (fast, no DB query)
  _role := (auth.jwt() -> 'app_metadata' ->> 'role');
  IF _role IN ('superadmin', 'employee') THEN
    RETURN TRUE;
  END IF;

  -- Fallback: query auth.users directly (bypasses profiles table RLS)
  SELECT (raw_app_meta_data ->> 'role') INTO _role
  FROM auth.users
  WHERE id = auth.uid();

  RETURN _role IN ('superadmin', 'employee');
END;
$$;
