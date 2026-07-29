-- Per-user in-app subscription system
-- Users get 30-day free trial, then pay for premium features
-- Churches pay K1500 once-off for their subscription (already exists)

-- 1. User subscription tracking
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'silver', 'gold')),
  trial_started_at TIMESTAMPTZ DEFAULT now(),
  trial_ends_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '30 days'),
  subscription_started_at TIMESTAMPTZ,
  subscription_ends_at TIMESTAMPTZ,
  payment_amount NUMERIC,
  payment_reference TEXT,
  payment_status TEXT DEFAULT 'none' CHECK (payment_status IN ('none', 'pending', 'approved', 'rejected')),
  auto_renew BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

-- 2. User subscription payments (MoMo TXID submissions)
CREATE TABLE IF NOT EXISTS user_subscription_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('silver', 'gold')),
  amount NUMERIC NOT NULL,
  payment_reference TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Feature definitions (what each tier gets)
CREATE TABLE IF NOT EXISTS feature_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_key TEXT NOT NULL UNIQUE,
  feature_name TEXT NOT NULL,
  min_tier TEXT NOT NULL DEFAULT 'silver' CHECK (min_tier IN ('free', 'silver', 'gold')),
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. RLS
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscription_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_tiers ENABLE ROW LEVEL SECURITY;

DO $ BEGIN CREATE POLICY "user_subscriptions_own" ON user_subscriptions; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (auth.uid() = user_id);

DO $ BEGIN CREATE POLICY "user_subscription_payments_own" ON user_subscription_payments; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR SELECT USING (auth.uid() = user_id);

DO $ BEGIN CREATE POLICY "user_subscription_payments_insert" ON user_subscription_payments; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DO $ BEGIN CREATE POLICY "feature_tiers_select" ON feature_tiers; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR SELECT USING (true);

DO $ BEGIN CREATE POLICY "feature_tiers_manage" ON feature_tiers; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin'))
  );

-- Superadmin can manage all subscriptions
DO $ BEGIN CREATE POLICY "superadmin_manage_subscriptions" ON user_subscriptions; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

DO $ BEGIN CREATE POLICY "superadmin_manage_payments" ON user_subscription_payments; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

-- 5. RPC: Check if user has access to a feature
CREATE OR REPLACE FUNCTION user_has_feature_access(feature_key TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  user_tier TEXT;
  required_tier TEXT;
  user_trial_ends TIMESTAMPTZ;
  user_sub_ends TIMESTAMPTZ;
  user_payment_status TEXT;
BEGIN
  -- Get user's current tier
  SELECT tier, trial_ends_at, subscription_ends_at, payment_status
  INTO user_tier, user_trial_ends, user_sub_ends, user_payment_status
  FROM user_subscriptions
  WHERE user_id = auth.uid();

  -- If no subscription record, default to free with trial
  IF user_tier IS NULL THEN
    user_tier := 'free';
    user_trial_ends := now() + INTERVAL '30 days';
  END IF;

  -- Check if trial is still active (all features unlocked during trial)
  IF user_trial_ends IS NOT NULL AND now() < user_trial_ends THEN
    RETURN true;
  END IF;

  -- Check if paid subscription is active
  IF user_tier IN ('silver', 'gold') AND user_sub_ends IS NOT NULL AND now() < user_sub_ends THEN
    -- Get required tier for this feature
    SELECT min_tier INTO required_tier FROM feature_tiers WHERE feature_key = $1 AND is_active = true;
    IF required_tier IS NULL THEN RETURN true; END IF; -- Feature not gated
    IF user_tier = 'gold' THEN RETURN true; END IF; -- Gold gets everything
    IF user_tier = 'silver' AND required_tier IN ('free', 'silver') THEN RETURN true; END IF;
    RETURN false;
  END IF;

  -- Free tier or expired: check if feature is free
  SELECT min_tier INTO required_tier FROM feature_tiers WHERE feature_key = $1 AND is_active = true;
  IF required_tier IS NULL OR required_tier = 'free' THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Subscribe user to a tier
CREATE OR REPLACE FUNCTION subscribe_user_to_tier(
  p_tier TEXT,
  p_payment_ref TEXT,
  p_amount NUMERIC
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_duration INTERVAL;
  v_result JSONB;
BEGIN
  -- Determine duration based on tier
  IF p_tier = 'silver' THEN
    v_duration := INTERVAL '30 days';
  ELSIF p_tier = 'gold' THEN
    v_duration := INTERVAL '365 days';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid tier');
  END IF;

  -- Upsert subscription
  INSERT INTO user_subscriptions (user_id, tier, subscription_started_at, subscription_ends_at, payment_amount, payment_reference, payment_status)
  VALUES (v_user_id, p_tier, now(), now() + v_duration, p_amount, p_payment_ref, 'pending')
  ON CONFLICT (user_id) DO UPDATE SET
    tier = p_tier,
    subscription_started_at = now(),
    subscription_ends_at = now() + v_duration,
    payment_amount = p_amount,
    payment_reference = p_payment_ref,
    payment_status = 'pending',
    updated_at = now();

  -- Log the payment
  INSERT INTO user_subscription_payments (user_id, tier, amount, payment_reference, status)
  VALUES (v_user_id, p_tier, p_amount, p_payment_ref, 'pending');

  RETURN jsonb_build_object('success', true, 'message', 'Payment submitted. Awaiting approval.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Seed feature tier definitions
INSERT INTO feature_tiers (feature_key, feature_name, min_tier, description) VALUES
  ('live_streaming', 'Live Streaming', 'silver', 'Watch and participate in live church services'),
  ('church_website', 'Church Website Builder', 'silver', 'Create a custom website for your church'),
  ('volunteer_scheduling', 'Volunteer Scheduling', 'silver', 'Manage volunteer schedules and sign-ups'),
  ('ai_sermon_notes', 'AI Sermon Notes', 'silver', 'AI-powered sermon summaries and study prompts'),
  ('crm_donor_management', 'CRM & Donor Management', 'silver', 'Track donors, giving history, and generate statements'),
  ('advanced_analytics', 'Advanced Analytics', 'gold', 'Detailed engagement and giving analytics'),
  ('priority_support', 'Priority Support', 'gold', 'Get priority customer support'),
  ('custom_branding', 'Custom Branding', 'gold', 'Fully custom app branding for your church')
ON CONFLICT (feature_key) DO NOTHING;
