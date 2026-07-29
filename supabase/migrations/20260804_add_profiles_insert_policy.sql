-- Allow authenticated users to create their own profile row.
-- Fixes "new row violates row-level security" thrown by ProfileNotifier's
-- auto-insert fallback (lib/core/providers/profile_provider.dart) when a
-- profile row is missing (the handle_new_user trigger missed this user, or
-- they predate it). Without this, the ONLY INSERT path is the
-- "Superadmins and employees can manage all profiles" FOR ALL policy whose
-- WITH CHECK (public.is_admin_or_employee()) is false for regular members,
-- so the insert is rejected and both the Profile and Giving tabs error out.

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);
