-- ==============================================================
-- 1. Plan columns on churches
-- ==============================================================
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'silver'
  CHECK (plan IN ('silver', 'gold', 'platinum'));

ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS onboarding_fee_paid BOOLEAN DEFAULT false;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS onboarding_fee_paid_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS promotion_platinum_until TIMESTAMPTZ;

-- ==============================================================
-- 2. tenant_balances table (SMS credits, future add-ons)
-- ==============================================================
CREATE TABLE IF NOT EXISTS public.tenant_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE UNIQUE,
  sms_credits INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.tenant_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_balances_select"
  ON public.tenant_balances FOR SELECT
  USING (
    auth.uid() IN (
      SELECT id FROM public.profiles
      WHERE tenant_id = tenant_balances.tenant_id
    )
  );

-- ==============================================================
-- 3. Tenant SMS transactions ledger
-- ==============================================================
CREATE TABLE IF NOT EXISTS public.tenant_sms_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('purchase', 'usage', 'refund', 'expiry')),
  description TEXT,
  payment_ref TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.tenant_sms_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_sms_transactions_select"
  ON public.tenant_sms_transactions FOR SELECT
  USING (
    auth.uid() IN (
      SELECT id FROM public.profiles
      WHERE tenant_id = tenant_sms_transactions.tenant_id
    )
  );

-- ==============================================================
-- 4. RPC: add SMS credits (called by Edge Function after payment)
-- ==============================================================
CREATE OR REPLACE FUNCTION public.add_sms_credits(
  p_tenant_id UUID,
  p_credits INTEGER,
  p_payment_ref TEXT DEFAULT NULL
)
RETURNS VOID
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.tenant_balances (tenant_id, sms_credits)
  VALUES (p_tenant_id, p_credits)
  ON CONFLICT (tenant_id)
  DO UPDATE SET sms_credits = tenant_balances.sms_credits + p_credits,
                updated_at = now();

  INSERT INTO public.tenant_sms_transactions (tenant_id, amount, type, description, payment_ref)
  VALUES (p_tenant_id, p_credits, 'purchase', 'SMS credit purchase', p_payment_ref);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_sms_credits FROM anon, authenticated;

-- ==============================================================
-- 5. RPC: deduct SMS credits (called by send-sms Edge Function)
-- ==============================================================
CREATE OR REPLACE FUNCTION public.deduct_sms_credits(
  p_tenant_id UUID,
  p_credits INTEGER
)
RETURNS BOOLEAN
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_balance INTEGER;
BEGIN
  SELECT sms_credits INTO v_balance
  FROM public.tenant_balances
  WHERE tenant_id = p_tenant_id;

  IF v_balance IS NULL OR v_balance < p_credits THEN
    RETURN false;
  END IF;

  UPDATE public.tenant_balances
  SET sms_credits = sms_credits - p_credits,
      updated_at = now()
  WHERE tenant_id = p_tenant_id;

  INSERT INTO public.tenant_sms_transactions (tenant_id, amount, type, description)
  VALUES (p_tenant_id, -p_credits, 'usage', 'SMS broadcast');

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.deduct_sms_credits FROM anon, authenticated;

-- ==============================================================
-- 6. RPC: get tenant balance
-- ==============================================================
CREATE OR REPLACE FUNCTION public.get_tenant_balance(p_tenant_id UUID)
RETURNS TABLE(sms_credits INTEGER)
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT COALESCE(tb.sms_credits, 0)
  FROM public.tenant_balances tb
  WHERE tb.tenant_id = p_tenant_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_tenant_balance FROM anon;
