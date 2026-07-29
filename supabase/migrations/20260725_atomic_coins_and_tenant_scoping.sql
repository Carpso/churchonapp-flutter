-- Atomic coin deduction with row-level locking to prevent race conditions
-- This replaces the unsafe read-then-write pattern in coins_service.dart
CREATE OR REPLACE FUNCTION deduct_coins_atomic(p_user_id UUID, p_amount INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_coins INT;
BEGIN
  -- Lock the row for this user to prevent concurrent modifications
  SELECT coins INTO current_coins
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF current_coins IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  IF current_coins < p_amount THEN
    RAISE EXCEPTION 'Insufficient coins. Current: %, Requested: %', current_coins, p_amount;
  END IF;

  UPDATE profiles
  SET coins = coins - p_amount
  WHERE id = p_user_id;
END;
$$;

-- Atomic coin redemption with row-level locking (used by redeemAtBookshop / redeemAtMerchStore)
CREATE OR REPLACE FUNCTION redeem_coins_atomic(
  p_user_id UUID,
  p_amount INT,
  p_redemption_type TEXT,
  p_partner_id TEXT,
  p_description TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_coins INT;
BEGIN
  SELECT coins INTO current_coins
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF current_coins IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  IF current_coins < p_amount THEN
    RAISE EXCEPTION 'Insufficient coins. Current: %, Requested: %', current_coins, p_amount;
  END IF;

  UPDATE profiles
  SET coins = coins - p_amount
  WHERE id = p_user_id;

  INSERT INTO coin_redemptions (user_id, amount, redemption_type, partner_id, description, status)
  VALUES (p_user_id, p_amount, p_redemption_type, p_partner_id, p_description, 'completed');
END;
$$;
