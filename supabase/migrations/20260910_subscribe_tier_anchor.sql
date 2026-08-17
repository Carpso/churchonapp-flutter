-- 20260910 — FIX: subscribe_user_to_tier free-gold bypass
-- (audit follow-up, 2026-08-17)
--
-- PROBLEM: subscribe_user_to_tier immediately set
--   subscription_ends_at = now() + 365 days
-- with payment_status = 'pending' and a client-supplied payment_ref/amount.
-- user_has_feature_access() only checked the DATES — never the payment
-- status — so any caller could grant themselves gold for free.
--
-- FIX (client is untrusted — mirror buy-sms-credits anchoring):
--   1. subscribe_user_to_tier now REQUIRES the payment ref to be anchored
--      to a CONFIRMED coa_payments row (own user, status
--      approved/completed/confirmed/settled, amount >= claimed price).
--      No anchor => no subscription, no pending grant.
--   2. On success the subscription is written as PAID (not pending) with
--      the server-verified amount.
--   3. user_has_feature_access (defense in depth) now also requires
--      payment_status in the paid set, not just dates.
--   4. Price anchors come from platform_settings (user_silver_monthly_price,
--      user_gold_yearly_price) with the historical defaults.

CREATE OR REPLACE FUNCTION public.subscribe_user_to_tier(p_tier text, p_payment_ref text, p_amount numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_duration INTERVAL;
  v_required NUMERIC;
  v_anchor RECORD;
  v_price_key TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF p_payment_ref IS NULL OR p_payment_ref = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing payment reference');
  END IF;

  -- Determine duration + required price based on tier
  IF p_tier = 'silver' THEN
    v_duration := INTERVAL '30 days';
    v_price_key := 'user_silver_monthly_price';
  ELSIF p_tier = 'gold' THEN
    v_duration := INTERVAL '365 days';
    v_price_key := 'user_gold_yearly_price';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid tier');
  END IF;

  SELECT value::NUMERIC INTO v_required
  FROM public.platform_settings WHERE key = v_price_key;
  v_required := COALESCE(v_required, CASE WHEN p_tier = 'silver' THEN 50 ELSE 500 END);

  -- Anchor: the payment MUST exist as a confirmed coa_payments row for
  -- THIS user, with an amount >= the required price. Never trust a
  -- client-supplied ref/amount on its own.
  SELECT * INTO v_anchor FROM public.coa_payments
  WHERE payment_ref = p_payment_ref
    AND user_id = v_user_id
    AND amount >= v_required - 0.01
    AND status IN ('approved', 'completed', 'confirmed', 'settled')
  ORDER BY created_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Payment not confirmed. Please complete payment first.'
    );
  END IF;

  -- Upsert subscription as PAID with server-verified amount
  INSERT INTO user_subscriptions (user_id, tier, subscription_started_at, subscription_ends_at, payment_amount, payment_reference, payment_status)
  VALUES (v_user_id, p_tier, now(), now() + v_duration, v_anchor.amount, p_payment_ref, 'paid')
  ON CONFLICT (user_id) DO UPDATE SET
    tier = p_tier,
    subscription_started_at = now(),
    subscription_ends_at = now() + v_duration,
    payment_amount = EXCLUDED.payment_amount,
    payment_reference = EXCLUDED.payment_reference,
    payment_status = 'paid',
    updated_at = now();

  -- Log the payment (confirmed)
  INSERT INTO user_subscription_payments (user_id, tier, amount, payment_reference, status)
  VALUES (v_user_id, p_tier, v_anchor.amount, p_payment_ref, 'paid');

  RETURN jsonb_build_object('success', true, 'message', 'Subscription activated.');
END;
$function$;

-- Defense in depth: paid-tier access requires payment_status in the paid set
CREATE OR REPLACE FUNCTION public.user_has_feature_access(feature_key text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_tier TEXT;
  required_tier TEXT;
  user_trial_ends TIMESTAMPTZ;
  user_sub_ends TIMESTAMPTZ;
  user_payment_status TEXT;
  v_feature_key TEXT := feature_key;
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

  -- Check if paid subscription is active (dates AND confirmed payment)
  IF user_tier IN ('silver', 'gold')
     AND user_sub_ends IS NOT NULL AND now() < user_sub_ends
     AND COALESCE(user_payment_status, '') IN ('paid', 'approved', 'completed', 'confirmed', 'settled') THEN
    -- Get required tier for this feature
    SELECT min_tier INTO required_tier FROM feature_tiers WHERE feature_key = v_feature_key AND is_active = true;
    IF required_tier IS NULL THEN RETURN true; END IF; -- Feature not gated
    IF user_tier = 'gold' THEN RETURN true; END IF; -- Gold gets everything
    IF user_tier = 'silver' AND required_tier IN ('free', 'silver') THEN RETURN true; END IF;
    RETURN false;
  END IF;

  -- Free tier or expired: check if feature is free
  SELECT min_tier INTO required_tier FROM feature_tiers WHERE feature_key = v_feature_key AND is_active = true;
  IF required_tier IS NULL OR required_tier = 'free' THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$function$;

REVOKE ALL ON FUNCTION public.subscribe_user_to_tier(TEXT, TEXT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.subscribe_user_to_tier(TEXT, TEXT, NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.user_has_feature_access(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_feature_access(TEXT) TO authenticated;
