-- 20261037: Fix 42P17 infinite recursion in profiles RLS.
--
-- Root cause: get_my_tenant_id() is SECURITY DEFINER but still queries
-- public.profiles. When RLS is active for the function owner, that SELECT
-- re-evaluates the profiles policies, including profiles_select_same_tenant
-- which calls get_my_tenant_id() again → infinite recursion (42P17).
--
-- Fix: rewrite get_my_tenant_id() to read from auth.users raw_app_meta_data
-- and/or the JWT claim instead of public.profiles. This completely avoids
-- touching the guarded table from within its own policy graph.

BEGIN;

-- Drop the recursive helper and recreate it against auth.users only.
CREATE OR REPLACE FUNCTION public.get_my_tenant_id()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tenant_id TEXT;
BEGIN
  -- 1. Prefer JWT app_metadata claim (fastest, no DB hit)
  v_tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id');
  IF v_tenant_id IS NOT NULL AND v_tenant_id <> '' THEN
    RETURN v_tenant_id;
  END IF;

  -- 2. Fallback: read from auth.users raw metadata. This bypasses RLS on
  --    public.profiles because it never queries that table.
  SELECT (raw_app_meta_data ->> 'tenant_id') INTO v_tenant_id
  FROM auth.users
  WHERE id = auth.uid();

  RETURN v_tenant_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_tenant_id() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_tenant_id() TO authenticated;

-- Ensure the same-tenant policy still exists; if it was dropped, recreate it
-- using the now-safe helper.
DROP POLICY IF EXISTS "profiles_select_same_tenant" ON public.profiles;
CREATE POLICY "profiles_select_same_tenant"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NOT NULL
    AND tenant_id::text = public.get_my_tenant_id()
    AND id != auth.uid()
  );

COMMIT;
