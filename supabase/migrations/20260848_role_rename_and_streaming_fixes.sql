-- Migration: Rename all 'employee' role to 'coa_employee' across profiles and role_assignments
-- This resolves the confusion between COA-level employees and tenant-level staff

-- 1. Rename existing users with 'employee' role to 'coa_employee'
UPDATE profiles SET role = 'coa_employee' WHERE role = 'employee';

-- 2. Rename in role_assignments
UPDATE role_assignments SET role_name = 'coa_employee' WHERE role_name = 'employee';

-- 3. Fix live_streams cross-tenant data leak (SEC-5/SEC-7)
-- Drop the USING (true) policy that lets everyone see all live streams
DO $$ BEGIN
  DROP POLICY IF EXISTS "live_streams_select" ON public.live_streams;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- Replace with tenant-scoped SELECT policy
DO $$ BEGIN
  DROP POLICY IF EXISTS "live_streams_select_tenant_scoped" ON public.live_streams;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "live_streams_select_tenant_scoped"
  ON public.live_streams FOR SELECT
  TO authenticated
  USING (
    church_id::text IN (
      SELECT tenant_id FROM profiles WHERE id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee')
    )
  );

-- Fix live_streams INSERT policy — allow pastors/bishops to create streams
DO $$ BEGIN
  DROP POLICY IF EXISTS "live_streams_manage" ON public.live_streams;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "live_streams_manage"
  ON public.live_streams FOR ALL
  TO authenticated
  USING (
    church_id::text IN (
      SELECT tenant_id FROM profiles WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee', 'pastor', 'bishop', 'admin')
    )
    OR EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee')
    )
  )
  WITH CHECK (
    church_id::text IN (
      SELECT tenant_id FROM profiles WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee', 'pastor', 'bishop', 'admin')
    )
    OR EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee')
    )
  );

-- 4. Fix church_storage_usage INSERT policy (SEC-10)
DO $$ BEGIN
  DROP POLICY IF EXISTS "System can insert storage usage" ON public.church_storage_usage;
  DROP POLICY IF EXISTS "Authenticated users can insert storage usage" ON public.church_storage_usage;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "Authenticated users can insert storage usage"
  ON public.church_storage_usage FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee')
    )
  );

-- 5. Add SET search_path = public to streaming SECURITY DEFINER functions
-- (Safe to re-create — these are idempotent)
DROP FUNCTION IF EXISTS public.get_streaming_usage(UUID);
CREATE OR REPLACE FUNCTION public.get_streaming_usage(p_church_id UUID)
RETURNS TABLE(minutes_used BIGINT, minutes_limit BIGINT, minutes_remaining BIGINT, can_stream BOOLEAN, week_start DATE)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start DATE := date_trunc('week', now())::date;
  v_used BIGINT;
  v_limit BIGINT;
BEGIN
  SELECT COALESCE(SUM(minutes), 0) INTO v_used
  FROM streaming_usage
  WHERE church_id = p_church_id AND week_start = v_week_start;

  -- Trial: 120 min/week, Paid: 480 min/week
  IF EXISTS (
    SELECT 1 FROM churches WHERE id = p_church_id
    AND subscription_ends_at > now()
    AND onboarding_fee_paid = true
  ) THEN
    v_limit := 480;
  ELSE
    v_limit := 120;
  END IF;

  RETURN QUERY SELECT
    v_used,
    v_limit,
    GREATEST(v_limit - v_used, 0),
    (v_used < v_limit),
    v_week_start;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_streaming_minutes(
  p_church_id UUID,
  p_minutes BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start DATE := date_trunc('week', now())::date;
BEGIN
  INSERT INTO streaming_usage (church_id, week_start, minutes)
  VALUES (p_church_id, v_week_start, p_minutes)
  ON CONFLICT (church_id, week_start)
  DO UPDATE SET minutes = streaming_usage.minutes + p_minutes;
END;
$$;

-- 6. Fix church_stream_config RLS to use tenant_id instead of church_id for profiles lookup
DO $$ BEGIN
  DROP POLICY IF EXISTS "Church admins can manage streaming config" ON public.church_stream_config;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "Church admins can manage streaming config"
  ON public.church_stream_config FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
      AND (p.tenant_id::uuid = church_stream_config.church_id OR p.role IN ('superadmin', 'coa_employee'))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
      AND (p.tenant_id::uuid = church_stream_config.church_id OR p.role IN ('superadmin', 'coa_employee'))
    )
  );
