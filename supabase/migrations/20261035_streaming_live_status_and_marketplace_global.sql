-- 20261035: Fix streaming viewer path + marketplace global + church_live_status RLS
-- Viewer never saw LIVE pill, marketplace global picks invisible, etc.

-- 1. church_live_status RLS (was ENABLE RLS with 0 policies → all ops 403)
ALTER TABLE IF EXISTS public.church_live_status ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view live status" ON public.church_live_status;
CREATE POLICY "Anyone can view live status"
  ON public.church_live_status FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Leaders can upsert live status" ON public.church_live_status;
CREATE POLICY "Leaders can upsert live status"
  ON public.church_live_status FOR INSERT TO authenticated
  WITH CHECK (
    church_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin','coa_employee'))
  );

DROP POLICY IF EXISTS "Leaders can update live status" ON public.church_live_status;
CREATE POLICY "Leaders can update live status"
  ON public.church_live_status FOR UPDATE TO authenticated
  USING (
    church_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin','coa_employee'))
  );

-- 2. Marketplace global picks: allow tenant_id IS NULL rows to be visible to all authenticated
-- (home Sparkle Picks + recommended global fallback). Previous policy required tenant_id IN profiles → global rows invisible.
DROP POLICY IF EXISTS "Marketplace items select tenant scoped" ON public.marketplace_items;
CREATE POLICY "Marketplace items select tenant scoped"
  ON public.marketplace_items FOR SELECT TO authenticated
  USING (
    status = 'active' AND (
      tenant_id IS NULL OR tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin','coa_employee','employee'))
    )
  );

-- 3. Ensure productsProvider fallback can fetch global items where tenant_id IS NULL
CREATE INDEX IF NOT EXISTS idx_marketplace_items_global ON public.marketplace_items(tenant_id) WHERE tenant_id IS NULL AND status='active';
