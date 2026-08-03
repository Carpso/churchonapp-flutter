-- P0-10: Fix profiles RLS — scope to same-tenant instead of USING (true)
-- This prevents mass data exposure of phone numbers, emails, FCM tokens

-- Drop the overly permissive policy
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view basic profile info" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- Users can only see their own full profile
CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- Users can see basic info (name, avatar, role) of same-tenant members
CREATE POLICY "Same tenant members visible"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NOT NULL
    AND tenant_id::text IN (
      SELECT p2.tenant_id FROM public.profiles p2 WHERE p2.id = auth.uid()
    )
    AND id != auth.uid()
  );

-- Also restrict anon access to profiles (should be none for production)
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anonymous users can view basic profiles" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
