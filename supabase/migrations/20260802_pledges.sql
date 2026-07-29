-- ═══════════════════════════════════════════════════════════════════════════
-- PLEDGES FEATURE
-- Members commit to give a total over a schedule (installments). Actual
-- installment payments move real money through the live Lipila collection
-- flow; the pledge itself tracks commitment vs. fulfillment in-app.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.pledges (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id       UUID REFERENCES public.churches(id) ON DELETE SET NULL,
  category        TEXT NOT NULL DEFAULT 'general',
  total_amount    NUMERIC(12,2) NOT NULL CHECK (total_amount > 0),
  amount_per_cycle NUMERIC(12,2) NOT NULL CHECK (amount_per_cycle > 0),
  frequency       TEXT NOT NULL CHECK (frequency IN ('weekly','monthly','quarterly')),
  installments    INT NOT NULL CHECK (installments > 0),
  paid_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  start_date      TIMESTAMPTZ NOT NULL DEFAULT now(),
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pledges_user ON public.pledges(user_id);
CREATE INDEX IF NOT EXISTS idx_pledges_tenant ON public.pledges(tenant_id);

ALTER TABLE public.pledges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own pledges" ON public.pledges;
CREATE POLICY "Users manage own pledges"
  ON public.pledges FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Leaders view tenant pledges" ON public.pledges;
CREATE POLICY "Leaders view tenant pledges"
  ON public.pledges FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::uuid = pledges.tenant_id
        AND p.role IN ('admin','pastor','bishop','general_treasurer','general_secretary','superadmin','employee')
    )
  );
