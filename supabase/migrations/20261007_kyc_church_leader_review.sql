-- 20261007 — Let church leaders (pastor/bishop/apostle/prophet/general_secretary/
-- admin) verify the KYC/identity of members in their OWN church, in addition to
-- superadmin/coa_employee. Uses SECURITY DEFINER helpers (reads auth.users + a
-- tenant lookup) to avoid the profiles 42P17 self-referential-policy recursion.

-- 1. Is the caller an approved KYC reviewer? (platform + church leadership)
CREATE OR REPLACE FUNCTION public.is_church_kyc_reviewer()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE caller_role text;
BEGIN
  SELECT COALESCE(
      (u.raw_app_meta_data->>'role'),
      (u.raw_app_meta_data->>'app_role'),
      u.role,
      'member'
    ) INTO caller_role
  FROM auth.users u
  WHERE u.id = auth.uid();

  RETURN caller_role IN (
    'superadmin','super_admin','employee','coa_employee',
    'pastor','bishop','apostle','prophet','general_secretary','admin'
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.is_church_kyc_reviewer() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_church_kyc_reviewer() FROM PUBLIC;

-- 2. Does the caller belong to the same church/tenant as the target user?
-- (SECURITY DEFINER on auth.users source for roles; tenant compare on profiles)
CREATE OR REPLACE FUNCTION public.is_same_tenant_member(target_uid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE caller_tenant text; target_tenant text;
BEGIN
  SELECT tenant_id INTO caller_tenant FROM public.profiles WHERE id = auth.uid();
  SELECT tenant_id INTO target_tenant FROM public.profiles WHERE id = target_uid;
  RETURN caller_tenant IS NOT NULL AND caller_tenant <> '' AND caller_tenant = target_tenant;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.is_same_tenant_member(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_same_tenant_member(uuid) FROM PUBLIC;

-- 3. kyc_documents: allow church leaders to SELECT documents of their own members
DROP POLICY IF EXISTS "Church leaders can view own-tenant KYC documents" ON public.kyc_documents;
CREATE POLICY "Church leaders can view own-tenant KYC documents"
  ON public.kyc_documents FOR SELECT
  TO authenticated
  USING (
    public.is_church_kyc_reviewer()
    AND public.is_same_tenant_member(user_id)
  );

-- 4. kyc_documents: allow church leaders to UPDATE (approve/reject) own-tenant docs
DROP POLICY IF EXISTS "Church leaders can update own-tenant KYC documents" ON public.kyc_documents;
CREATE POLICY "Church leaders can update own-tenant KYC documents"
  ON public.kyc_documents FOR UPDATE
  TO authenticated
  USING (
    public.is_church_kyc_reviewer()
    AND public.is_same_tenant_member(user_id)
  );

-- 5. profiles: allow church leaders to update verification fields of own-tenant
-- members. Since targets can only be members of the caller's tenant, and callers
-- are validated via auth.users (no profiles recursion), this is safe.
DROP POLICY IF EXISTS "Church leaders can verify own-tenant members" ON public.profiles;
CREATE POLICY "Church leaders can verify own-tenant members"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (
    public.is_church_kyc_reviewer()
    AND public.is_same_tenant_member(id)
  )
  WITH CHECK (
    public.is_church_kyc_reviewer()
    AND public.is_same_tenant_member(id)
  );
