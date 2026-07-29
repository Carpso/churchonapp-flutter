-- Create church_quiz_competitions table if not exists
CREATE TABLE IF NOT EXISTS public.church_quiz_competitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id TEXT NOT NULL,
  tenant_id UUID REFERENCES public.tenants(id),
  title TEXT NOT NULL,
  date TIMESTAMPTZ NOT NULL,
  question_count INTEGER NOT NULL DEFAULT 10,
  difficulty TEXT,
  entry_fee DOUBLE PRECISION NOT NULL DEFAULT 0,
  pin_code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'upcoming',
  created_by UUID REFERENCES auth.users(id) NOT NULL,
  max_participants INTEGER DEFAULT 50,
  prize_description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.church_quiz_competitions ENABLE ROW LEVEL SECURITY;

-- RLS: authenticated users can read competitions they created or belong to their church
DROP POLICY IF EXISTS "Users can view their church competitions" ON public.church_quiz_competitions;
CREATE POLICY "Users can view their church competitions" ON public.church_quiz_competitions
  FOR SELECT USING (
    created_by = auth.uid()
    OR church_id IN (
      SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
    )
  );

-- RLS: authenticated users can insert competitions for their church
DROP POLICY IF EXISTS "Users can create competitions" ON public.church_quiz_competitions;
CREATE POLICY "Users can create competitions" ON public.church_quiz_competitions
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND (
      church_id IN (
        SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
      )
    )
  );

-- RLS: competition creator can update their competition
DROP POLICY IF EXISTS "Creators can update their competitions" ON public.church_quiz_competitions;
CREATE POLICY "Creators can update their competitions" ON public.church_quiz_competitions
  FOR UPDATE USING (created_by = auth.uid());

-- Fix settlement phone resolution: add fallback to churches table
CREATE OR REPLACE FUNCTION public.resolve_settlement_phone(p_tenant_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
BEGIN
  -- Try churches.payout_mobile first
  SELECT payout_mobile INTO v_phone FROM public.churches WHERE tenant_id = p_tenant_id AND payout_mobile IS NOT NULL LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  -- Try churches.treasurer_phone
  SELECT treasurer_phone INTO v_phone FROM public.churches WHERE tenant_id = p_tenant_id AND treasurer_phone IS NOT NULL LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  -- Try pastor/admin profile phone
  SELECT phone_number INTO v_phone FROM public.profiles
    WHERE tenant_id = p_tenant_id::text
      AND role IN ('pastor', 'bishop', 'admin')
      AND phone_number IS NOT NULL
    LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  RETURN NULL;
END;
$$;
