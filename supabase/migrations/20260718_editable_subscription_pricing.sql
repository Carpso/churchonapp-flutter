-- Editable subscription pricing for superadmin/COA employees
-- Stores all configurable prices in platform_settings table

-- 1. Add subscription pricing columns to platform_settings
INSERT INTO platform_settings (key, value, updated_at) VALUES
  ('user_silver_monthly_price', '150', now()),
  ('user_gold_yearly_price', '1500', now()),
  ('user_silver_monthly_label', 'K150/month', now()),
  ('user_gold_yearly_label', 'K1,500/year', now()),
  ('church_subscription_price', '1500', now()),
  ('church_subscription_label', 'K1,500 once-off', now()),
  ('meeting_monthly_price', '150', now()),
  ('meeting_yearly_price', '1500', now()),
  ('fasting_monthly_price', '100', now()),
  ('fasting_per_session_price', '25', now()),
  ('coin_exchange_rate', '10', now()),
  ('subscription_trial_days', '30', now()),
  ('max_free_features', '5', now())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

-- 2. RPC: Get all subscription pricing
CREATE OR REPLACE FUNCTION get_subscription_pricing()
RETURNS JSONB AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_object_agg(key, value) INTO result
  FROM platform_settings
  WHERE key IN (
    'user_silver_monthly_price',
    'user_gold_yearly_price',
    'user_silver_monthly_label',
    'user_gold_yearly_label',
    'church_subscription_price',
    'church_subscription_label',
    'meeting_monthly_price',
    'meeting_yearly_price',
    'fasting_monthly_price',
    'fasting_per_session_price',
    'coin_exchange_rate',
    'subscription_trial_days',
    'max_free_features'
  );

  RETURN COALESCE(result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. RPC: Update subscription pricing (superadmin only)
CREATE OR REPLACE FUNCTION update_subscription_pricing(
  p_settings JSONB
)
RETURNS JSONB AS $$
DECLARE
  key TEXT;
  value TEXT;
BEGIN
  -- Check if user is superadmin
  IF NOT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Update each setting
  FOR key, value IN SELECT * FROM jsonb_each_text(p_settings)
  LOOP
    INSERT INTO platform_settings (key, value, updated_at)
    VALUES (key, value, now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  END LOOP;

  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
