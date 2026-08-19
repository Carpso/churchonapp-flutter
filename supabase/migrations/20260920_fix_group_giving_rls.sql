-- 20260920: group_contributions RLS used `tenant_id::uuid` on profiles.tenant_id,
-- which THROWS for seed churches (text ids like 'zm_1') and kills the
-- group-giving stream/list. Compare as text like 20260843 pattern.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Tenant members can view group contributions" ON public.group_contributions;
  DROP POLICY IF EXISTS "Tenant admins can create group contributions" ON public.group_contributions;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "Tenant members can view group contributions"
ON public.group_contributions
FOR SELECT
TO authenticated
USING (
  tenant_id::text IN (SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid())
);

CREATE POLICY "Tenant admins can create group contributions"
ON public.group_contributions
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee', 'employee', 'admin', 'pastor', 'bishop')
      AND tenant_id::text = group_contributions.tenant_id::text
  )
);