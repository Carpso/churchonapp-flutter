-- ═══════════════════════════════════════════════════════════════════════════════
-- FINAL RLS AUDIT FIX — closes all remaining security gaps
-- ═══════════════════════════════════════════════════════════════════════════════

-- =============================================================================
-- PART 1: Fix overly permissive INSERT policies (WITH CHECK true)
-- =============================================================================

-- 1a. Notifications — only insert for self
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
CREATE POLICY "Users can insert own notifications"
    ON public.notifications FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 1b. Wallet transactions — only insert for own user_id
DROP POLICY IF EXISTS "Users can insert own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Users can insert own wallet transactions"
    ON public.wallet_transactions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 1c. Service reports — only insert with own reporter_id
DROP POLICY IF EXISTS "Authenticated users can submit service reports" ON public.service_reports;
CREATE POLICY "Authenticated users can submit service reports"
    ON public.service_reports FOR INSERT
    WITH CHECK (auth.uid() = reporter_id);

-- 1d. Pastor reports — only insert with own pastor_id
DROP POLICY IF EXISTS "Authenticated users can submit pastor reports" ON public.pastor_reports;
CREATE POLICY "Authenticated users can submit pastor reports"
    ON public.pastor_reports FOR INSERT
    WITH CHECK (auth.uid() = pastor_id);

-- =============================================================================
-- PART 2: Fix fundraising policies — missing user_id ownership checks
-- =============================================================================

-- 2a. Fundraising contributions — add contributor_id check
DROP POLICY IF EXISTS "Users can contribute" ON public.fundraising_contributions;
CREATE POLICY "Users can contribute"
    ON public.fundraising_contributions FOR INSERT
    WITH CHECK (auth.uid() = contributor_id);

-- 2b. Group contribution members — add user_id check
DROP POLICY IF EXISTS "Users can join groups" ON public.group_contribution_members;
CREATE POLICY "Users can join groups"
    ON public.group_contribution_members FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 2c. Group contribution payments — add user_id check via member subquery
DROP POLICY IF EXISTS "Users can contribute to groups" ON public.group_contribution_payments;
CREATE POLICY "Users can contribute to groups"
    ON public.group_contribution_payments FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.group_contribution_members m
            WHERE m.id = group_contribution_payments.member_id
            AND m.user_id = auth.uid()
        )
    );

-- 2d. Fundraising ventures — fix wrong tenant_id comparison
DROP POLICY IF EXISTS "Anyone can view active ventures" ON public.fundraising_ventures;
CREATE POLICY "Anyone can view active ventures"
    ON public.fundraising_ventures FOR SELECT
    USING (
        status = 'active' OR
        EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.tenant_id::uuid = fundraising_ventures.tenant_id
        )
    );

-- 2e. Fundraising invites — fix wrong tenant_id comparison
DROP POLICY IF EXISTS "Tenants can view their invites" ON public.fundraising_invites;
CREATE POLICY "Tenants can view their invites"
    ON public.fundraising_invites FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND (
                p.tenant_id::uuid = fundraising_invites.to_tenant_id OR
                p.tenant_id::uuid = fundraising_invites.from_tenant_id
            )
        )
    );

-- =============================================================================
-- PART 3: Replace auth.jwt() -> 'role' with profile-based DB lookups
-- =============================================================================

-- 3a. Admin audit log — use profiles table instead of JWT claim
DROP POLICY IF EXISTS "Superadmins and employees can view audit logs" ON public.admin_audit_log;
CREATE POLICY "Superadmins and employees can view audit logs"
    ON public.admin_audit_log FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 3b. Platform settings — use profiles table
DROP POLICY IF EXISTS "Superadmin employees can update platform settings" ON public.platform_settings;
CREATE POLICY "Superadmin employees can update platform settings"
    ON public.platform_settings FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 3c. Radio stations — use profiles table
DROP POLICY IF EXISTS "Superadmin employees can manage radio stations" ON public.radio_stations;
CREATE POLICY "Superadmin employees can manage radio stations"
    ON public.radio_stations FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- =============================================================================
-- PART 4: Add SET search_path to all SECURITY DEFINER functions
-- (These are already created in 20260709, 20260707, 20260702, 2026062801, 20260708)
-- =============================================================================

-- 4a. increment_fundraising_raised (20260709_fundraising_feature.sql)
CREATE OR REPLACE FUNCTION public.increment_fundraising_raised(venture_id UUID, amount DOUBLE PRECISION)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE fundraising_ventures
  SET raised_amount = raised_amount + amount
  WHERE id = venture_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4b. increment_group_collected (20260709_fundraising_feature.sql)
CREATE OR REPLACE FUNCTION public.increment_group_collected(group_id UUID, amount DOUBLE PRECISION)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE group_contributions
  SET collected_amount = collected_amount + amount
  WHERE id = group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4c. increment_member_paid (20260709_fundraising_feature.sql)
CREATE OR REPLACE FUNCTION public.increment_member_paid(member_id UUID, amount DOUBLE PRECISION)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE group_contribution_members
  SET paid_amount = paid_amount + amount
  WHERE id = member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4d. set_church_trial (20260709_role_hierarchy_marketplace_trial.sql)
CREATE OR REPLACE FUNCTION public.set_church_trial()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  IF NEW.trial_started_at IS NULL THEN
    NEW.trial_started_at := now();
    NEW.trial_ends_at := now() + INTERVAL '30 days';
    NEW.subscription_status := 'trial';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4e. is_church_trial_active (20260709_role_hierarchy_marketplace_trial.sql)
CREATE OR REPLACE FUNCTION public.is_church_trial_active(church_id UUID)
RETURNS BOOLEAN
SET search_path = public
AS $$
DECLARE
    church_record public.churches%ROWTYPE;
BEGIN
    SELECT * INTO church_record FROM public.churches WHERE id = church_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    IF church_record.subscription_status = 'active' THEN
        RETURN true;
    END IF;
    IF church_record.subscription_status = 'trial' AND church_record.trial_ends_at > now() THEN
        RETURN true;
    END IF;
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4f. notify_role_approved (20260709_role_hierarchy_marketplace_trial.sql)
CREATE OR REPLACE FUNCTION public.notify_role_approved()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, reference_id)
  VALUES (
    NEW.user_id,
    'role_approved',
    'Role Approved',
    'Your ' || NEW.role_name || ' role has been approved.',
    NEW.id::text
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4g. notify_writer_approved (20260709_role_hierarchy_marketplace_trial.sql)
CREATE OR REPLACE FUNCTION public.notify_writer_approved()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, reference_id)
  VALUES (
    NEW.user_id,
    'writer_approved',
    'Writer Application Approved',
    'Your writer application has been approved.',
    NEW.id::text
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4h. notify_profile_role_change (20260709_role_hierarchy_marketplace_trial.sql)
CREATE OR REPLACE FUNCTION public.notify_profile_role_change()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    INSERT INTO public.notifications (user_id, type, title, body, reference_id)
    VALUES (
      NEW.id,
      'role_changed',
      'Role Updated',
      'Your role has been updated to ' || COALESCE(NEW.role, 'member') || '.',
      NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4i. link_pre_registration (2026062801_feature_fixes.sql)
CREATE OR REPLACE FUNCTION public.link_pre_registration()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  UPDATE public.pre_registrations
  SET linked_user_id = NEW.id, linked_at = now(), status = 'linked'
  WHERE phone = NEW.raw_user_meta_data->>'phone'
    AND status = 'pending'
    AND linked_user_id IS NULL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4j. is_system_locked (20260708_notifications_jobs_ads_shutdown.sql)
CREATE OR REPLACE FUNCTION public.is_system_locked()
RETURNS BOOLEAN
SET search_path = public
AS $$
DECLARE
  lock_status TEXT;
BEGIN
  SELECT value INTO lock_status FROM public.platform_settings WHERE key = 'system_lockdown';
  RETURN COALESCE(lock_status, 'false') = 'true';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4k. check_admin_rate_limit (20260707_sessions_login_history_rate_limit.sql)
CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(admin_id UUID)
RETURNS BOOLEAN
SET search_path = public
AS $$
DECLARE
  recent_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO recent_count
  FROM public.admin_audit_log
  WHERE admin_id = check_admin_rate_limit.admin_id
    AND created_at > now() - INTERVAL '1 minute';
  RETURN recent_count < 30;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4l. check_role_change_permission (20260707_sessions_login_history_rate_limit.sql)
CREATE OR REPLACE FUNCTION public.check_role_change_permission(target_user_id UUID, new_role TEXT)
RETURNS BOOLEAN
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.role IN ('superadmin', 'employee')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4m. add_coins (20260702_user_activities_2fa_coins.sql)
DROP FUNCTION IF EXISTS public.add_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.add_coins(user_id UUID, amount INTEGER)
RETURNS VOID
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET coins = COALESCE(coins, 0) + amount
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- PART 5: Church trial — reset on superadmin approval
-- =============================================================================

-- Extend set_church_trial to also fire on UPDATE when is_verified changes
DROP TRIGGER IF EXISTS trg_set_church_trial ON public.churches;
CREATE TRIGGER trg_set_church_trial
  BEFORE INSERT ON public.churches
  FOR EACH ROW EXECUTE FUNCTION public.set_church_trial();

-- Function to reset trial when superadmin approves a church
CREATE OR REPLACE FUNCTION public.reset_church_trial_on_approval()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
  IF OLD.is_verified IS DISTINCT FROM true AND NEW.is_verified = true THEN
    NEW.trial_started_at := now();
    NEW.trial_ends_at := now() + INTERVAL '30 days';
    NEW.subscription_status := 'trial';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_reset_church_trial_on_approval ON public.churches;
CREATE TRIGGER trg_reset_church_trial_on_approval
  BEFORE UPDATE ON public.churches
  FOR EACH ROW
  WHEN (OLD.is_verified IS DISTINCT FROM true AND NEW.is_verified = true)
  EXECUTE FUNCTION public.reset_church_trial_on_approval();

-- =============================================================================
-- PART 6: Ensure all tables have RLS enabled
-- =============================================================================

ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tithe_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lenco_payouts ENABLE ROW LEVEL SECURITY;
