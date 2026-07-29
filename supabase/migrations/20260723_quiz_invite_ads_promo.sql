-- 1) Add invite_code to pvp_matches for deep-link invites
ALTER TABLE IF EXISTS public.pvp_matches
  ADD COLUMN IF NOT EXISTS invite_code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS is_invite BOOLEAN DEFAULT false;

-- 2) Platform-wide promo campaigns table
CREATE TABLE IF NOT EXISTS public.promo_campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    campaign_type TEXT NOT NULL CHECK (campaign_type IN (
        'referral', 'registration_bonus', 'promo_code', 'seasonal', 'ad_campaign'
    )),
    promo_code TEXT UNIQUE,
    discount_percent INTEGER,
    discount_amount_zmw NUMERIC(12,2),
    bonus_coins INTEGER DEFAULT 0,
    budget_zmw NUMERIC(14,2),
    budget_spent_zmw NUMERIC(14,2) DEFAULT 0,
    max_redemptions INTEGER,
    current_redemptions INTEGER DEFAULT 0,
    min_quiz_score INTEGER,
    target_audience TEXT DEFAULT 'all' CHECK (target_audience IN ('all', 'new_users', 'existing_users', 'employees', 'superadmins')),
    is_active BOOLEAN DEFAULT true,
    starts_at TIMESTAMPTZ DEFAULT now(),
    ends_at TIMESTAMPTZ,
    image_url TEXT,
    target_url TEXT,
    placement TEXT DEFAULT 'home' CHECK (placement IN ('home', 'quiz', 'events', 'marketplace', 'all')),
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3) Promo redemption tracking
CREATE TABLE IF NOT EXISTS public.promo_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.promo_campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    redeemed_at TIMESTAMPTZ DEFAULT now(),
    reward_type TEXT,
    reward_amount NUMERIC(14,2),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(campaign_id, user_id)
);

-- 4) Platform ads (for superadmin/COA — tenant_id is NULL for platform-wide)
ALTER TABLE IF EXISTS public.tenant_ads
  ADD COLUMN IF NOT EXISTS is_platform_wide BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS budget_zmw NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS budget_spent_zmw NUMERIC(14,2) DEFAULT 0;

-- RLS policies for promo_campaigns
ALTER TABLE public.promo_campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active promo campaigns" ON public.promo_campaigns;
CREATE POLICY "Anyone can view active promo campaigns" ON public.promo_campaigns
    FOR SELECT USING (is_active = true AND (ends_at IS NULL OR ends_at > now()));

DROP POLICY IF EXISTS "Superadmins and employees can manage promo campaigns" ON public.promo_campaigns;
CREATE POLICY "Superadmins and employees can manage promo campaigns" ON public.promo_campaigns
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role IN ('superadmin', 'coa_employee')
        )
    );

-- RLS for promo_redemptions
ALTER TABLE public.promo_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own redemptions" ON public.promo_redemptions;
CREATE POLICY "Users can view own redemptions" ON public.promo_redemptions
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own redemptions" ON public.promo_redemptions;
CREATE POLICY "Users can insert own redemptions" ON public.promo_redemptions
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Superadmins and employees can view all redemptions" ON public.promo_redemptions;
CREATE POLICY "Superadmins and employees can view all redemptions" ON public.promo_redemptions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role IN ('superadmin', 'coa_employee')
        )
    );

-- Update tenant_ads RLS to allow superadmin/COA to see all platform ads
DROP POLICY IF EXISTS "Superadmins and employees can manage ads" ON public.tenant_ads;
CREATE POLICY "Superadmins and employees can manage ads" ON public.tenant_ads
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role IN ('superadmin', 'coa_employee')
        )
    );

-- Enable realtime for new tables (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'promo_campaigns'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.promo_campaigns;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'promo_redemptions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.promo_redemptions;
    END IF;
END;
$$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_promo_campaigns_active ON public.promo_campaigns(is_active, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_promo_campaigns_code ON public.promo_campaigns(promo_code) WHERE promo_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_user ON public.promo_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_campaign ON public.promo_redemptions(campaign_id);

-- RPC: increment promo redemption counter
CREATE OR REPLACE FUNCTION public.increment_promo_redemption(campaign_id_str TEXT, amount NUMERIC)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.promo_campaigns
    SET
        current_redemptions = current_redemptions + 1,
        budget_spent_zmw = budget_spent_zmw + COALESCE(amount, 0)
    WHERE id = campaign_id_str::UUID;
END;
$$;

-- RPC: award coins to user
CREATE OR REPLACE FUNCTION public.award_coins(user_id_str TEXT, amount INTEGER, reason_str TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.profiles
    SET coins = COALESCE(coins, 0) + amount
    WHERE id = user_id_str::UUID;
END;
$$;
