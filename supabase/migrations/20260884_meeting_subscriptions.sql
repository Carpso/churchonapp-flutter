-- Pro Business Meeting subscriptions table.
CREATE TABLE IF NOT EXISTS public.meeting_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  plan_type TEXT NOT NULL DEFAULT 'monthly',
  amount_zmw NUMERIC DEFAULT 0,
  payment_ref TEXT,
  status TEXT DEFAULT 'active',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.meeting_subscriptions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'meeting_subscriptions' AND cmd = 'SELECT') THEN
    CREATE POLICY "meeting_subscriptions_select_own" ON public.meeting_subscriptions
      FOR SELECT TO authenticated USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'meeting_subscriptions' AND cmd = 'INSERT') THEN
    CREATE POLICY "meeting_subscriptions_insert_own" ON public.meeting_subscriptions
      FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
