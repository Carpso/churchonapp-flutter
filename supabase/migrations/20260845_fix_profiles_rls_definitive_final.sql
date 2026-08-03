-- ════════════════════════════════════════════════════════════════════════════
-- MIGRATION: 20260845_fix_profiles_rls_definitive_final.sql
-- DESCRIPTION: Definitive fix for 42P17 "infinite recursion detected in policy
--              for relation profiles".
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Helper function: verify if user is admin or employee without reading public.profiles
--    Queries auth.users raw_app_meta_data or JWT claims directly to eliminate recursion.
CREATE OR REPLACE FUNCTION public.is_admin_or_employee()
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  _role TEXT;
BEGIN
  -- 1. Check JWT app_metadata claim (fastest)
  _role := (auth.jwt() -> 'app_metadata' ->> 'role');
  IF _role IN ('superadmin', 'super_admin', 'employee', 'coa_employee') THEN
    RETURN TRUE;
  END IF;

  -- 2. Fallback: Query auth.users directly (bypasses RLS completely)
  SELECT (raw_app_meta_data ->> 'role') INTO _role
  FROM auth.users
  WHERE id = auth.uid();

  RETURN COALESCE(_role, 'member') IN ('superadmin', 'super_admin', 'employee', 'coa_employee');
END;
$$;

-- 2. Helper function: check super admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  RETURN public.is_admin_or_employee();
END;
$$;

-- 3. Clean up existing profiles policies to avoid duplicates/stale policies
DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can view basic profile info" ON public.profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_all_admin" ON public.profiles;

-- 4. Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 5. Recreate safe policies for profiles
-- 5a. Users can select their own profile OR any authenticated user can view basic profile info
CREATE POLICY "Anyone can view basic profile info"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

-- 5b. Users can insert their own profile row
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- 5c. Users can update their own profile row
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 5d. Superadmins & employees can manage all profiles (FOR ALL)
CREATE POLICY "Superadmins and employees can manage all profiles"
  ON public.profiles FOR ALL
  TO authenticated
  USING (public.is_admin_or_employee())
  WITH CHECK (public.is_admin_or_employee());

-- 6. Update policies on other tables that had inline subqueries to profiles causing 42P17 recursion

-- 6a. platform_settings
DROP POLICY IF EXISTS "Admins can view platform settings" ON public.platform_settings;
DROP POLICY IF EXISTS "Admins can manage platform settings" ON public.platform_settings;
DROP POLICY IF EXISTS "Admins can update platform settings" ON public.platform_settings;
DROP POLICY IF EXISTS "Anyone can view platform settings" ON public.platform_settings;

CREATE POLICY "Admins can view platform settings"
    ON public.platform_settings FOR SELECT
    TO authenticated
    USING (public.is_admin_or_employee());

CREATE POLICY "Admins can manage platform settings"
    ON public.platform_settings FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6b. radio_stations
DROP POLICY IF EXISTS "Admins can manage radio stations" ON public.radio_stations;

CREATE POLICY "Admins can manage radio stations"
    ON public.radio_stations FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6c. quiz_seasons
DROP POLICY IF EXISTS "quiz_seasons_select" ON public.quiz_seasons;
DROP POLICY IF EXISTS "Admins can manage quiz seasons" ON public.quiz_seasons;

CREATE POLICY "Admins can manage quiz seasons"
    ON public.quiz_seasons FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6d. quiz_weekly_scores
DROP POLICY IF EXISTS "quiz_weekly_scores_select" ON public.quiz_weekly_scores;
DROP POLICY IF EXISTS "Admins can manage quiz weekly scores" ON public.quiz_weekly_scores;

CREATE POLICY "Admins can manage quiz weekly scores"
    ON public.quiz_weekly_scores FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6e. bible_study_sessions
DROP POLICY IF EXISTS "bible_study_sessions_select" ON public.bible_study_sessions;
DROP POLICY IF EXISTS "Admins can manage bible study sessions" ON public.bible_study_sessions;

CREATE POLICY "Admins can manage bible study sessions"
    ON public.bible_study_sessions FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6f. notification_channels
DROP POLICY IF EXISTS "notification_channels_select" ON public.notification_channels;
DROP POLICY IF EXISTS "Admins can manage notification channels" ON public.notification_channels;

CREATE POLICY "Admins can manage notification channels"
    ON public.notification_channels FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6g. game_scores
DROP POLICY IF EXISTS "game_scores_select" ON public.game_scores;
DROP POLICY IF EXISTS "Admins can manage game scores" ON public.game_scores;

CREATE POLICY "Admins can manage game scores"
    ON public.game_scores FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6h. quiz_season_rewards
DROP POLICY IF EXISTS "quiz_season_rewards_select" ON public.quiz_season_rewards;
DROP POLICY IF EXISTS "Admins can manage quiz season rewards" ON public.quiz_season_rewards;

CREATE POLICY "Admins can manage quiz season rewards"
    ON public.quiz_season_rewards FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6i. daily_bible_verses
DROP POLICY IF EXISTS "Authenticated users can update daily bible verses" ON public.daily_bible_verses;
DROP POLICY IF EXISTS "Admins can manage daily bible verses" ON public.daily_bible_verses;

CREATE POLICY "Admins can manage daily bible verses"
    ON public.daily_bible_verses FOR ALL
    TO authenticated
    USING (public.is_admin_or_employee())
    WITH CHECK (public.is_admin_or_employee());

-- 6j. user_sessions
DROP POLICY IF EXISTS "Admins can view all sessions" ON public.user_sessions;

CREATE POLICY "Admins can view all sessions"
    ON public.user_sessions FOR SELECT
    TO authenticated
    USING (public.is_admin_or_employee());

-- 7. Grant execute permission on security definer functions to authenticated users
GRANT EXECUTE ON FUNCTION public.is_admin_or_employee() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

COMMIT;
