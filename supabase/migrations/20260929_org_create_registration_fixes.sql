-- 20260929: org creation for bishops + churches schema drift fix
-- 1) create_organization RPC: leadership-gated, auto-links the caller's church
-- 2) churches columns used by the registration client but missing from repo migrations

-- Ensure every column the registration client writes/reads exists (idempotent).
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS country TEXT,
  ADD COLUMN IF NOT EXISTS treasurer_phone TEXT,
  ADD COLUMN IF NOT EXISTS logo TEXT,
  ADD COLUMN IF NOT EXISTS settings JSONB;

-- Leadership-gated organization creation. The caller becomes bishop_id and
-- their own church (by tenant) is auto-linked so the new org has its first branch.
CREATE OR REPLACE FUNCTION public.create_organization(p_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := gen_random_uuid();
  v_caller UUID := auth.uid();
  v_tenant TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_caller
      AND role IN ('superadmin','super_admin','employee','coa_employee',
                   'bishop','apostle','general_secretary','pastor','admin')
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'Organization name is required';
  END IF;

  INSERT INTO public.organizations (id, name, bishop_id, created_at)
  VALUES (v_org_id, trim(p_name), v_caller, now());

  SELECT tenant_id INTO v_tenant FROM public.profiles WHERE id = v_caller;

  IF v_tenant IS NOT NULL THEN
    UPDATE public.churches
    SET organization_id = v_org_id
    WHERE tenant_id = v_tenant::uuid
      AND organization_id IS NULL;
  END IF;

  RETURN v_org_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_organization FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_organization TO authenticated;

-- The 5-minute inactivity lockout signed users out of the whole app whenever
-- they read/listened/watched without tapping or backgrounded the app briefly.
-- Raise to 30 minutes (client also pauses the countdown while backgrounded).
INSERT INTO platform_settings (key, value) VALUES
  ('session_inactivity_minutes', '30')
ON CONFLICT (key) DO UPDATE SET value = '30';