-- ═══════════════════════════════════════════════════════════════════════════════
-- SECURITY HARDENING (2026-08-13)
-- 1. Guard coin RPCs: add_coins / deduct_coins now require auth.uid() = owner
--    and a bounded amount (was: unlimited minting by any authenticated user).
-- 2. Tighten coa_payments INSERT: authenticated users may only insert their
--    OWN rows with status 'pending'. Confirmed statuses are set only by the
--    webhook / superadmin UPDATE (already enforced).
-- 3. SET search_path = public on all recent SECURITY DEFINER functions
--    (function_search_path_mutable — prevents search_path hijacking).
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── 1. Guard coin RPCs ─────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.add_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.add_coins(user_id UUID, amount INTEGER)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Not authorized: can only modify your own coins';
  END IF;
  IF amount IS NULL OR amount > 100000 OR amount < -100000 THEN
    RAISE EXCEPTION 'Coin amount out of bounds (max 100000)';
  END IF;
  UPDATE public.profiles
  SET coins = COALESCE(coins, 0) + amount,
      balance_cc = COALESCE(balance_cc, 0) + amount
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION public.add_coins(UUID, INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.add_coins(UUID, INTEGER) FROM PUBLIC;

DROP FUNCTION IF EXISTS public.deduct_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.deduct_coins(user_id UUID, amount INTEGER)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Not authorized: can only modify your own coins';
  END IF;
  IF amount IS NULL OR amount > 100000 OR amount < -100000 THEN
    RAISE EXCEPTION 'Coin amount out of bounds (max 100000)';
  END IF;
  UPDATE public.profiles
  SET coins = GREATEST(COALESCE(coins, 0) - amount, 0),
      balance_cc = GREATEST(COALESCE(balance_cc, 0) - amount, 0)
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION public.deduct_coins(UUID, INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.deduct_coins(UUID, INTEGER) FROM PUBLIC;

-- ── 2. Tighten coa_payments INSERT policy ──────────────────────────────────────
-- Clients may only insert their own rows in 'pending' state. A confirmed status
-- (approved/completed/confirmed/settled) can only be written by the Lipila
-- webhook / superadmin via the existing UPDATE policy — so a member can never
-- forge a verified payment to anchor a fraudulent payout.
DO $$
BEGIN
  DROP POLICY IF EXISTS "coa_payments_insert" ON public.coa_payments;
  CREATE POLICY "coa_payments_insert" ON public.coa_payments FOR INSERT WITH CHECK (
    (auth.uid() = user_id AND status = 'pending')
    OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 3. SET search_path on recent SECURITY DEFINER functions ────────────────────
DO $$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.proname IN (
        'get_my_tenant_id', 'get_church_monthly_stats', 'get_church_monthly_tithes',
        'get_organization_church_member_counts', 'get_organization_missions',
        'sp_validate_import_columns', 'get_church_service_summary',
        'get_organization_service_summary', 'get_coa_payment_stats',
        'kids_upsert_progress', 'get_platform_engagement_stats',
        'kids_mark_resource_completed', 'increment_study_attendees', 'get_quiz_leaderboard'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER SET search_path = public', f.signature);
  END LOOP;
END $$;
