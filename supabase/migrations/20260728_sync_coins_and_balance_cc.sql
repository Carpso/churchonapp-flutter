-- Recreate add_coins and deduct_coins to sync both 'coins' and 'balance_cc' columns

CREATE OR REPLACE FUNCTION public.add_coins(user_id UUID, amount INTEGER)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET coins = COALESCE(coins, 0) + amount,
      balance_cc = COALESCE(balance_cc, 0) + amount
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.deduct_coins(user_id UUID, amount INTEGER)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET coins = GREATEST(COALESCE(coins, 0) - amount, 0),
      balance_cc = GREATEST(COALESCE(balance_cc, 0) - amount, 0)
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
