-- 1) User rewards table (audit trail)
CREATE TABLE IF NOT EXISTS public.user_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reward_type TEXT NOT NULL CHECK (reward_type IN ('coins', 'xp', 'badge', 'subscription_days', 'multiplier', 'custom')),
    amount NUMERIC(14,2) DEFAULT 0,
    title TEXT NOT NULL,
    description TEXT,
    badge_icon TEXT,
    granted_by UUID REFERENCES auth.users(id),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2) Badge definitions for custom badges
CREATE TABLE IF NOT EXISTS public.badge_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    icon_url TEXT,
    color TEXT DEFAULT '#FFD700',
    category TEXT DEFAULT 'general',
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS for user_rewards
ALTER TABLE public.user_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own rewards" ON public.user_rewards;
CREATE POLICY "Users can view own rewards" ON public.user_rewards
    FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Superadmins and employees can manage rewards" ON public.user_rewards;
CREATE POLICY "Superadmins and employees can manage rewards" ON public.user_rewards
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee'))
    );

-- RLS for badge_definitions
ALTER TABLE public.badge_definitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view badges" ON public.badge_definitions;
CREATE POLICY "Anyone can view badges" ON public.badge_definitions
    FOR SELECT USING (true);
DROP POLICY IF EXISTS "Superadmins and employees can manage badges" ON public.badge_definitions;
CREATE POLICY "Superadmins and employees can manage badges" ON public.badge_definitions
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee'))
    );

-- 3) RPC: award coins to user (for rewards system)
CREATE OR REPLACE FUNCTION public.award_user_coins(
    target_user_id TEXT,
    coin_amount INTEGER,
    reason_title TEXT DEFAULT 'Reward',
    reason_desc TEXT DEFAULT '',
    granter_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.profiles
    SET coins = COALESCE(coins, 0) + coin_amount
    WHERE id = target_user_id::UUID;

    INSERT INTO public.user_rewards (user_id, reward_type, amount, title, description, granted_by)
    VALUES (target_user_id::UUID, 'coins', coin_amount, reason_title, reason_desc, granter_id::UUID);
END;
$$;

-- 4) RPC: award XP to user
CREATE OR REPLACE FUNCTION public.award_user_xp(
    target_user_id TEXT,
    xp_amount INTEGER,
    reason_title TEXT DEFAULT 'XP Reward',
    reason_desc TEXT DEFAULT '',
    granter_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.profiles
    SET xp = COALESCE(xp, 0) + xp_amount
    WHERE id = target_user_id::UUID;

    INSERT INTO public.user_rewards (user_id, reward_type, amount, title, description, granted_by)
    VALUES (target_user_id::UUID, 'xp', xp_amount, reason_title, reason_desc, granter_id::UUID);
END;
$$;

-- 5) Enable realtime for new tables
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'user_rewards'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.user_rewards;
    END IF;
END;
$$;

-- 6) Ensure Rock of Ages church has all tenant fields populated
UPDATE public.churches
SET
    logo_url = COALESCE(logo_url, 'https://media.churchonapp.com/churches/rock_of_ages.png'),
    primary_color = COALESCE(primary_color, '#1A1A2E'),
    accent_color = COALESCE(accent_color, '#FFD700'),
    surface_color = COALESCE(surface_color, '#16213E'),
    treasurer_phone = COALESCE(treasurer_phone, '+260975000001'),
    payout_mobile = COALESCE(payout_mobile, '+260975000000'),
    payout_network = COALESCE(payout_network, 'MTN'),
    latitude = COALESCE(latitude, -15.3875),
    longitude = COALESCE(longitude, 28.3228)
WHERE slug = 'rock-of-ages-kabulonga';

-- 7) Index for rewards queries
CREATE INDEX IF NOT EXISTS idx_user_rewards_user ON public.user_rewards(user_id);
CREATE INDEX IF NOT EXISTS idx_user_rewards_created ON public.user_rewards(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_badge_definitions_active ON public.badge_definitions(is_active);
