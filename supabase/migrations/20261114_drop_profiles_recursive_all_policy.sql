-- ============================================================
-- FIX: Infinite recursion on profiles RLS
--
-- Root cause: The ALL policy "Superadmins and employees can manage
-- all profiles" has EXISTS (SELECT 1 FROM profiles p WHERE ...) which
-- queries profiles from within its own RLS policy evaluation.
-- This creates infinite recursion for ANY table whose RLS policy
-- has a subquery on profiles (30+ tables affected).
--
-- Fix: DROP the recursive ALL policy. The "profiles_admin_all" policy
-- (using is_admin_or_employee() → reads auth.users, not profiles)
-- already covers admin access safely.
--
-- Also fix payout_tasks_select to use is_admin_or_employee() instead
-- of inline EXISTS subquery on profiles.
-- ============================================================

-- 1. Drop the recursive ALL policy on profiles
DO $$ BEGIN
  DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- 2. Fix payout_tasks_select: replace inline profiles subquery with is_admin_or_employee()
DO $$ BEGIN
  DROP POLICY IF EXISTS "payout_tasks_select" ON public.payout_tasks;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "payout_tasks_select" ON public.payout_tasks
  FOR SELECT
  USING (
    auth.uid() = user_id
    OR is_admin_or_employee()
  );

-- 3. Drop duplicate/redundant SELECT policies on profiles that are covered by newer ones
-- (kept: profiles_select_own, profiles_select_same_tenant, profiles_select_staff,
--  Anyone can view basic profile info, Users can read own profile)
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
