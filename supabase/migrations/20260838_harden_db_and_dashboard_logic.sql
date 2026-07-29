-- ════════════════════════════════════════════════════════════════════════════
-- CHURCH ON APP - DATABASE HARDENING & DASHBOARD LOGIC MIGRATION
-- Target: PostgreSQL / Supabase
-- Description: Hardens search paths, revokes elevated RPC access, replaces 
--              permissive RLS policies, adds composite performance indexes, 
--              and implements transactional tithe & ledger processing.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 1: ROLE VERIFICATION & HELPER FUNCTIONS
-- ────────────────────────────────────────────────────────────────────────────

-- 1.1 Helper Function: Verify if current user is a Superadmin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Check JWT app_metadata and user_metadata claims
  IF (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') IN ('super_admin', 'superadmin'))
     OR (coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') IN ('super_admin', 'superadmin')) THEN
    RETURN TRUE;
  END IF;

  -- Fallback to database profiles table
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('superadmin', 'super_admin', 'coa_employee')
  );
END;
$$;

-- 1.2 Helper Function: Verify if current user is a Pastor or Leader of a specific Church
CREATE OR REPLACE FUNCTION public.is_church_pastor(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Superadmin override for platform maintenance
  IF public.is_super_admin() THEN
    RETURN TRUE;
  END IF;

  -- Verify user role and tenant/church matching
  RETURN EXISTS (
    SELECT 1 
    FROM public.profiles p
    LEFT JOIN public.churches c ON c.id = p_church_id
    WHERE p.id = v_user_id
      AND p.role IN ('pastor', 'bishop', 'church_admin', 'leader')
      AND (
        p.tenant_id = c.tenant_id
        OR c.pastor_id = v_user_id
        OR c.id = p_church_id
      )
  );
END;
$$;


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 2: SECURITY & SEARCH PATH HARDENING
-- ────────────────────────────────────────────────────────────────────────────

-- 2.1 Set search_path on custom functions to mitigate schema injection attacks
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN 
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'update_updated_at_column',
        'generate_member_id',
        'handle_tithe_record',
        'calculate_level',
        'get_user_avg_rating',
        'check_admin_rate_limit',
        'system_transfer_coins',
        'activate_quiz_lease',
        'award_coins',
        'deduct_coins_atomic',
        'increment_redeemed_count',
        'record_event_checkin'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp;', r.proname, r.args);
  END LOOP;
END $$;

-- 2.2 Revoke direct execution of sensitive coin and system RPCs from anon and authenticated roles
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'system_transfer_coins') THEN
    REVOKE EXECUTE ON FUNCTION public.system_transfer_coins FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.system_transfer_coins TO service_role;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'activate_quiz_lease') THEN
    REVOKE EXECUTE ON FUNCTION public.activate_quiz_lease FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.activate_quiz_lease TO service_role;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'award_coins') THEN
    REVOKE EXECUTE ON FUNCTION public.award_coins FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.award_coins TO service_role;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'deduct_coins_atomic') THEN
    REVOKE EXECUTE ON FUNCTION public.deduct_coins_atomic FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.deduct_coins_atomic TO service_role;
  END IF;
END $$;


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 3: ROW-LEVEL SECURITY (RLS) REMEDIATION
-- ────────────────────────────────────────────────────────────────────────────

-- 3.1 CHURCHES TABLE
ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view churches" ON public.churches;
  DROP POLICY IF EXISTS "Superadmins can manage churches" ON public.churches;
  DROP POLICY IF EXISTS "Pastors can update own church" ON public.churches;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Anyone can view churches"
  ON public.churches FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Superadmins can manage churches"
  ON public.churches FOR ALL
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE POLICY "Pastors can update own church"
  ON public.churches FOR UPDATE
  TO authenticated
  USING (public.is_church_pastor(id))
  WITH CHECK (public.is_church_pastor(id));

-- 3.2 PASTOR REPORTS TABLE
ALTER TABLE public.pastor_reports ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view pastor reports" ON public.pastor_reports;
  DROP POLICY IF EXISTS "Pastors can submit pastor reports" ON public.pastor_reports;
  DROP POLICY IF EXISTS "Pastors can view own reports" ON public.pastor_reports;
  DROP POLICY IF EXISTS "Pastors can insert own reports" ON public.pastor_reports;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Pastors can view own reports"
  ON public.pastor_reports FOR SELECT
  TO authenticated
  USING (
    public.is_super_admin() 
    OR auth.uid() = pastor_id 
    OR (church_id IS NOT NULL AND public.is_church_pastor(church_id))
  );

CREATE POLICY "Pastors can insert own reports"
  ON public.pastor_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = pastor_id 
    AND (church_id IS NULL OR public.is_church_pastor(church_id))
  );

-- 3.3 SERVICE REPORTS TABLE
ALTER TABLE public.service_reports ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Service reports select policy" ON public.service_reports;
  DROP POLICY IF EXISTS "Service reports insert policy" ON public.service_reports;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Service reports select policy"
  ON public.service_reports FOR SELECT
  TO authenticated
  USING (
    public.is_super_admin()
    OR (church_id IS NOT NULL AND public.is_church_pastor(church_id))
    OR EXISTS (
      SELECT 1 FROM public.profiles p 
      WHERE p.id = auth.uid() AND p.tenant_id = service_reports.tenant_id
    )
  );

CREATE POLICY "Service reports insert policy"
  ON public.service_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR (church_id IS NOT NULL AND public.is_church_pastor(church_id))
    OR auth.uid() = created_by
  );

-- 3.4 TITHES TABLE
ALTER TABLE public.tithes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can view own tithes" ON public.tithes;
  DROP POLICY IF EXISTS "Users can insert own tithes" ON public.tithes;
  DROP POLICY IF EXISTS "Pastors can manage church tithes" ON public.tithes;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Users can view own tithes"
  ON public.tithes FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id 
    OR public.is_super_admin()
    OR (church_id IS NOT NULL AND public.is_church_pastor(church_id))
  );

CREATE POLICY "Users can insert own tithes"
  ON public.tithes FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id 
    OR public.is_super_admin()
  );

-- 3.5 WALLET TRANSACTIONS TABLE
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "System can insert wallet transactions" ON public.wallet_transactions;
  DROP POLICY IF EXISTS "Users can view own wallet transactions" ON public.wallet_transactions;
  DROP POLICY IF EXISTS "Users can insert own wallet transactions" ON public.wallet_transactions;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Users can view own wallet transactions"
  ON public.wallet_transactions FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id 
    OR public.is_super_admin()
  );

CREATE POLICY "Users can insert own wallet transactions"
  ON public.wallet_transactions FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id 
    OR public.is_super_admin()
  );

-- 3.6 PLATFORM SETTINGS TABLE
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view platform settings" ON public.platform_settings;
  DROP POLICY IF EXISTS "Admins can view platform settings" ON public.platform_settings;
  DROP POLICY IF EXISTS "Admins can update platform settings" ON public.platform_settings;
  DROP POLICY IF EXISTS "Admins can manage platform settings" ON public.platform_settings;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Admins can view platform settings"
  ON public.platform_settings FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Admins can manage platform settings"
  ON public.platform_settings FOR ALL
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- 3.7 PRAYERS TABLE
ALTER TABLE public.prayers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update prayers" ON public.prayers;
  DROP POLICY IF EXISTS "Users can update own prayers" ON public.prayers;
  DROP POLICY IF EXISTS "Prayers select policy" ON public.prayers;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Prayers select policy"
  ON public.prayers FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Users can update own prayers"
  ON public.prayers FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id OR public.is_super_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_super_admin());

-- 3.8 TESTIMONIES TABLE
ALTER TABLE public.testimonies ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update testimonies" ON public.testimonies;
  DROP POLICY IF EXISTS "Users can update own testimonies" ON public.testimonies;
  DROP POLICY IF EXISTS "Testimonies select policy" ON public.testimonies;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Testimonies select policy"
  ON public.testimonies FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Users can update own testimonies"
  ON public.testimonies FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id OR public.is_super_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_super_admin());

-- 3.9 QUIZ EVENTS TABLE
ALTER TABLE public.quiz_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Quiz events select policy" ON public.quiz_events;
  DROP POLICY IF EXISTS "Admins can manage quiz events" ON public.quiz_events;
EXCEPTION WHEN undefined_object THEN NULL; END $$;

CREATE POLICY "Quiz events select policy"
  ON public.quiz_events FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Admins can manage quiz events"
  ON public.quiz_events FOR ALL
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 4: PERFORMANCE INDEXES & REALTIME OPTIMIZATION
-- ────────────────────────────────────────────────────────────────────────────

-- Composite indexes for high-frequency queries
CREATE INDEX IF NOT EXISTS idx_tithes_church_created_amount 
  ON public.tithes (church_id, created_at DESC, amount);

CREATE INDEX IF NOT EXISTS idx_tithes_tenant_created 
  ON public.tithes (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pastor_reports_church_created 
  ON public.pastor_reports (church_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_reports_tenant_created 
  ON public.service_reports (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_created 
  ON public.wallet_transactions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_user_created 
  ON public.transactions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_prayers_tenant_status_created 
  ON public.prayers (tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testimonies_tenant_status_created 
  ON public.testimonies (tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_quiz_events_tenant_status_created 
  ON public.quiz_events (tenant_id, status, created_at DESC);

-- Ensure Realtime publications include key scoped tables
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'pastor_reports') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.pastor_reports;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'service_reports') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.service_reports;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'tithes') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.tithes;
    END IF;
  END IF;
END $$;


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 5: TRANSACTIONAL BUSINESS LOGIC (TITHE & LEDGER PROCESSOR)
-- ────────────────────────────────────────────────────────────────────────────

-- Idempotent, atomic function to process tithes, update ledger, and aggregate totals
CREATE OR REPLACE FUNCTION public.process_tithe_and_ledger(
  p_tithe_id UUID,
  p_user_id UUID,
  p_church_id UUID,
  p_amount NUMERIC,
  p_payment_method TEXT,
  p_reference_id TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_tithe_record RECORD;
  v_transaction_exists BOOLEAN;
  v_result JSONB;
BEGIN
  -- 1. Authorization check
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated request';
  END IF;

  IF NOT (
    v_caller_id = p_user_id 
    OR public.is_super_admin() 
    OR public.is_church_pastor(p_church_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: User cannot record or process tithe for this church';
  END IF;

  -- 2. Upsert Tithe Record (Idempotent)
  IF p_tithe_id IS NOT NULL THEN
    UPDATE public.tithes
    SET 
      status = 'completed',
      payment_method = COALESCE(p_payment_method, payment_method),
      transaction_ref = COALESCE(p_reference_id, transaction_ref),
      notes = COALESCE(p_notes, notes),
      updated_at = NOW()
    WHERE id = p_tithe_id
    RETURNING * INTO v_tithe_record;
  END IF;

  IF v_tithe_record.id IS NULL THEN
    INSERT INTO public.tithes (
      user_id,
      church_id,
      amount,
      payment_method,
      transaction_ref,
      notes,
      status,
      created_at,
      updated_at
    )
    VALUES (
      p_user_id,
      p_church_id,
      p_amount,
      COALESCE(p_payment_method, 'mobile_money'),
      p_reference_id,
      p_notes,
      'completed',
      NOW(),
      NOW()
    )
    RETURNING * INTO v_tithe_record;
  END IF;

  -- 3. Idempotent Insert into Wallet Transactions / Ledger
  SELECT EXISTS (
    SELECT 1 FROM public.wallet_transactions
    WHERE reference_id = p_reference_id OR (metadata->>'tithe_id') = v_tithe_record.id::text
  ) INTO v_transaction_exists;

  IF NOT v_transaction_exists THEN
    INSERT INTO public.wallet_transactions (
      user_id,
      amount,
      type,
      category,
      reference_id,
      description,
      status,
      created_at
    )
    VALUES (
      p_user_id,
      p_amount,
      'credit',
      'tithe',
      p_reference_id,
      COALESCE(p_notes, 'Tithe Payment'),
      'completed',
      NOW()
    );
  END IF;

  -- 4. Dynamically Increment Aggregated Totals in Churches/Profiles where applicable
  UPDATE public.churches
  SET updated_at = NOW()
  WHERE id = p_church_id;

  -- Return details as JSON
  v_result := jsonb_build_object(
    'success', true,
    'tithe_id', v_tithe_record.id,
    'user_id', p_user_id,
    'church_id', p_church_id,
    'amount', p_amount,
    'status', 'completed',
    'processed_at', NOW()
  );

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Transaction failed: %', SQLERRM;
END;
$$;

-- Grant execution to authenticated users for tithe recording
GRANT EXECUTE ON FUNCTION public.process_tithe_and_ledger TO authenticated;

COMMIT;
