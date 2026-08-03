-- ════════════════════════════════════════════════════════════════════════════
-- MIGRATION: 20260855_fix_profiles_rls_infinite_recursion.sql
-- DESCRIPTION: Fixes 42P17 "infinite recursion detected in policy for relation
--              profiles" which caused HTTP 500 on every profiles query
--              (Profile tab + Give tab showed "check your connection").
--
-- ROOT CAUSE: The policy "Superadmins and employees can manage all profiles"
--             (from 20260723/20260814) used an INLINE SUBQUERY on profiles
--             inside its USING clause:
--               EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() ...)
--             Postgres rejects any policy that reads the table it guards.
--             The safe replacement (20260845) was never applied to prod.
--
-- ALSO FIXES: Removes the legacy USING (true) SELECT policies that exposed
--             ALL profile rows (phone numbers, FCM tokens) to every
--             authenticated user. Replaces with:
--               - own full profile
--               - same-tenant members (basic visibility, no recursion via
--                 SECURITY DEFINER helper)
--               - own insert / own update
--               - admin ALL via safe is_admin_or_employee() helper
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. Helper: returns the authenticated user's tenant_id (text)
--    SECURITY DEFINER so RLS is bypassed → no recursion when used
--    inside a profiles policy.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_tenant_id()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_tenant_id() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_tenant_id() TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 2. Drop ALL legacy profiles policies (clean slate)
-- ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can view basic profile info" ON public.profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Same tenant members visible" ON public.profiles;
DROP POLICY IF EXISTS "Anonymous users can view basic profiles" ON public.profiles;
DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_all_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_manage" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_delete" ON public.profiles;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ──────────────────────────────────────────────────────────────
-- 3. Recreate safe, non-recursive policies
-- ──────────────────────────────────────────────────────────────

-- 3a. Users can select their own full profile
DO $$ BEGIN
  DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
  DROP POLICY IF EXISTS "profiles_select_same_tenant" ON public.profiles;
  DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
  DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
  DROP POLICY IF EXISTS "profiles_admin_all" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- 3b. Users can view basic info of same-tenant members
--     (helper function bypasses RLS → no infinite recursion)
CREATE POLICY "profiles_select_same_tenant"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NOT NULL
    AND tenant_id::text = public.get_my_tenant_id()
    AND id != auth.uid()
  );

-- 3c. Users can insert their own profile row
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- 3d. Users can update their own profile row
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 3e. Admins & employees manage all profiles (safe helper — no recursion)
CREATE POLICY "profiles_admin_all"
  ON public.profiles FOR ALL
  TO authenticated
  USING (public.is_admin_or_employee())
  WITH CHECK (public.is_admin_or_employee());

COMMIT;
