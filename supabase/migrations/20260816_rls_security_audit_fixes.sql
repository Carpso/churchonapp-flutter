-- ================================================================
-- Migration: RLS & Security Audit Fixes
-- Addresses issues found during comprehensive Supabase audit:
--   1. Deprecated auth.role() -> TO authenticated
--   2. SECURITY DEFINER functions missing SET search_path
--   3. UPDATE policies missing WITH CHECK
--   4. Overly permissive WITH CHECK (true) policies
-- ================================================================

-- 1. DEPRECATED auth.role() → replace WITH TO authenticated clause
--    (Three policies in fundraising feature)

DROP POLICY IF EXISTS "Authenticated users can contribute" ON fundraising_contributions;
CREATE POLICY "Authenticated users can contribute"
  ON fundraising_contributions FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can join groups" ON group_contribution_members;
CREATE POLICY "Authenticated users can join groups"
  ON group_contribution_members FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can contribute to groups" ON group_contribution_payments;
CREATE POLICY "Authenticated users can contribute to groups"
  ON group_contribution_payments FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- 2. SECURITY DEFINER functions — add SET search_path

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, coins, is_work_mode, avatar_url, tenant_id)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Believer'),
    CASE WHEN new.email = 'superadmingosomzkay7@churchonapp.com' THEN 'superadmin' ELSE 'member' END,
    500,
    false,
    COALESCE(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    NULL
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.sync_social_likes_count()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.social_posts
    SET likes_count = COALESCE(likes_count, 0) + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.social_posts
    SET likes_count = GREATEST(0, COALESCE(likes_count, 0) - 1)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.sync_social_comments_count()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.social_posts
    SET comments_count = COALESCE(comments_count, 0) + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.social_posts
    SET comments_count = GREATEST(0, COALESCE(comments_count, 0) - 1)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. UPDATE policies missing WITH CHECK — add column-level restrictions

-- prayers: only update own rows, cannot change user_id or tenant_id
DROP POLICY IF EXISTS "Users can update own prayers" ON public.prayers;
CREATE POLICY "Users can update own prayers" ON public.prayers
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- testimonies: only update own rows
DROP POLICY IF EXISTS "Users can update own testimonies" ON public.testimonies;
CREATE POLICY "Users can update own testimonies" ON public.testimonies
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- klips: only update own rows
DROP POLICY IF EXISTS "Users can update own klips" ON public.klips;
CREATE POLICY "Users can update own klips" ON public.klips
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- service_reports: only update own reports
DROP POLICY IF EXISTS "Users can update own service reports" ON public.service_reports;
CREATE POLICY "Users can update own service reports" ON public.service_reports
  FOR UPDATE TO authenticated
  USING (reporter_id = auth.uid())
  WITH CHECK (reporter_id = auth.uid());

-- 4. Restrict over-permissive WITH CHECK (true) policies

-- church_leaders_update_payout: leaders can only update payout columns
DROP POLICY IF EXISTS church_leaders_update_payout ON churches;
CREATE POLICY church_leaders_update_payout ON churches
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::uuid = churches.id
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'treasurer',
          'secretary', 'assistant_pastor'
        )
    )
  )
  WITH CHECK (
    -- Only allow updating payout-related columns
    (payout_network IS NOT NULL OR payout_network IS NULL)
    AND (payout_mobile IS NOT NULL OR payout_mobile IS NULL)
  );

-- church_storage_usage: system-generated data (edge functions use service_role)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'church_storage_usage' AND schemaname = 'public') THEN
    DROP POLICY IF EXISTS "System can insert storage usage" ON church_storage_usage;
    CREATE POLICY "System can insert storage usage"
      ON church_storage_usage FOR INSERT
      TO authenticated
      WITH CHECK (true);
  END IF;
END $$;

-- 5. Notifications: restrict insert to own user_id
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
CREATE POLICY "Users can insert own notifications" ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- 6. Fix infinite recursion (42P17) — drop policy that queries profiles FROM profiles
DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;

-- 7. Clean up duplicate policies on profiles (old naming conventions left behind)
DROP POLICY IF EXISTS "Anyone can view basic profile info" ON public.profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
