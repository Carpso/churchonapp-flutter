-- 20260916 Fix churches UPDATE RLS — tenant admins could never update their
-- church (policies compared profiles.tenant_id to churches.id instead of
-- churches.tenant_id), which broke saving service schedules (hero card),
-- branding, payout details etc.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Church admins can update own church" ON public.churches;
END $$;

CREATE POLICY "Church admins can update own church" ON public.churches
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id IS NOT NULL
        AND p.tenant_id = churches.tenant_id::text
        AND p.role IN ('admin','pastor','bishop','superadmin','employee','coa_employee')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id IS NOT NULL
        AND p.tenant_id = churches.tenant_id::text
        AND p.role IN ('admin','pastor','bishop','superadmin','employee','coa_employee')
    )
  );

DO $$
BEGIN
  DROP POLICY IF EXISTS "church_leaders_update_payout" ON public.churches;
END $$;

CREATE POLICY "church_leaders_update_payout" ON public.churches
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id IS NOT NULL
        AND p.tenant_id = churches.tenant_id::text
        AND p.role IN ('admin','pastor','bishop','leader','general_treasurer','general_secretary','superadmin','employee','coa_employee','treasurer','secretary','assistant_pastor')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id IS NOT NULL
        AND p.tenant_id = churches.tenant_id::text
        AND p.role IN ('admin','pastor','bishop','leader','general_treasurer','general_secretary','superadmin','employee','coa_employee','treasurer','secretary','assistant_pastor')
    )
  );