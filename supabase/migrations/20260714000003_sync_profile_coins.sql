-- Sync coins and balance_cc columns, then add a trigger to keep them in sync

-- 1. Sync: make balance_cc the source of truth
UPDATE profiles
SET coins = GREATEST(COALESCE(balance_cc, 0), 0)::INTEGER
WHERE COALESCE(balance_cc, 0) != COALESCE(coins, 0);

-- Also fix any profiles where balance_cc is 0 but coins is not
UPDATE profiles
SET balance_cc = COALESCE(coins, 0)
WHERE COALESCE(balance_cc, 0) = 0 AND COALESCE(coins, 0) > 0;

-- 2. Trigger to keep both columns in sync
CREATE OR REPLACE FUNCTION sync_profile_coins()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.balance_cc IS DISTINCT FROM OLD.balance_cc THEN
    NEW.coins := GREATEST(COALESCE(NEW.balance_cc, 0), 0)::INTEGER;
  END IF;
  IF NEW.coins IS DISTINCT FROM OLD.coins THEN
    NEW.balance_cc := COALESCE(NEW.coins, 0)::DOUBLE PRECISION;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_coins ON profiles;
CREATE TRIGGER trg_sync_profile_coins
  BEFORE INSERT OR UPDATE OF coins, balance_cc ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_profile_coins();
