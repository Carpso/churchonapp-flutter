-- ═══════════════════════════════════════════════════════════════
-- CORE ARCHITECTURE UPGRADE
-- 1. System Lock / Freeze Switch
-- 2. Audit Logs
-- 3. Idempotent Transaction Pipeline
-- 4. Materialized Views for Reporting
-- 5. Tenant Lease Lifecycle
-- ═══════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────
-- 1. SYSTEM LOCK / FREEZE SWITCH
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.system_lock_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_locked BOOLEAN NOT NULL DEFAULT false,
  reason TEXT,
  locked_by UUID REFERENCES auth.users(id),
  locked_at TIMESTAMPTZ,
  unlock_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.system_lock_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "system_lock_state_superadmin_all" ON public.system_lock_state;
CREATE POLICY "system_lock_state_superadmin_all"
  ON public.system_lock_state FOR ALL
  TO authenticated
  USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin');

DROP POLICY IF EXISTS "system_lock_state_read_auth" ON public.system_lock_state;
CREATE POLICY "system_lock_state_read_auth"
  ON public.system_lock_state FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

INSERT INTO public.system_lock_state (is_locked) VALUES (false) ON CONFLICT DO NOTHING;

-- Freeze/unfreeze function
CREATE OR REPLACE FUNCTION public.toggle_system_freeze(
  p_locked BOOLEAN,
  p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.system_lock_state
  SET is_locked = p_locked,
      reason = p_reason,
      locked_by = v_admin_id,
      locked_at = CASE WHEN p_locked THEN now() ELSE NULL END,
      unlock_at = CASE WHEN p_locked THEN now() + interval '1 hour' ELSE NULL END
  WHERE id = (SELECT id FROM public.system_lock_state ORDER BY created_at DESC LIMIT 1);

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, CASE WHEN p_locked THEN 'system_freeze' ELSE 'system_unfreeze' END, 'system_lock_state', NULL,
          jsonb_build_object('reason', p_reason));

  RETURN p_locked;
END;
$$;

-- Check if system is locked (called by RPCs)
CREATE OR REPLACE FUNCTION public.is_system_locked()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_locked BOOLEAN;
BEGIN
  SELECT is_locked INTO v_locked
  FROM public.system_lock_state
  ORDER BY created_at DESC
  LIMIT 1;
  RETURN COALESCE(v_locked, false);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 2. AUDIT LOGS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  details JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_logs_admin_read" ON public.audit_logs;
CREATE POLICY "audit_logs_admin_read"
  ON public.audit_logs FOR SELECT
  TO authenticated
  USING (auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
      OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee');

DROP POLICY IF EXISTS "audit_logs_insert_auth" ON public.audit_logs;
CREATE POLICY "audit_logs_insert_auth"
  ON public.audit_logs FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- ────────────────────────────────────────────────────────────
-- 3. IDEMPOTENT TRANSACTION PIPELINE
-- ────────────────────────────────────────────────────────────

-- Prevent duplicate transactions via idempotency key
CREATE TABLE IF NOT EXISTS public.transaction_idempotency (
  idempotency_key TEXT PRIMARY KEY,
  transaction_id UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_idempotency_key ON public.transaction_idempotency(idempotency_key);

ALTER TABLE public.transaction_idempotency ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "idempotency_service_only" ON public.transaction_idempotency;
CREATE POLICY "idempotency_service_only"
  ON public.transaction_idempotency FOR ALL
  TO service_role
  USING (true);

-- Idempotent transaction insert
CREATE OR REPLACE FUNCTION public.insert_transaction_idempotent(
  p_idempotency_key TEXT,
  p_user_id UUID,
  p_tenant_id UUID,
  p_amount DOUBLE PRECISION,
  p_type TEXT,
  p_currency TEXT DEFAULT 'ZMW',
  p_payment_method TEXT DEFAULT NULL,
  p_payment_ref TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_platform_fee DOUBLE PRECISION DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id UUID;
  v_new_id UUID;
BEGIN
  -- Check idempotency first
  SELECT transaction_id INTO v_existing_id
  FROM public.transaction_idempotency
  WHERE idempotency_key = p_idempotency_key;

  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  -- Insert transaction
  v_new_id := gen_random_uuid();
  INSERT INTO public.transactions (id, user_id, tenant_id, amount, category, payment_method, reference, platform_fee, status, created_at)
  VALUES (v_new_id, p_user_id, p_tenant_id, p_amount, p_type, p_payment_method, p_payment_ref, p_platform_fee, 'completed', now());

  -- Record idempotency key
  INSERT INTO public.transaction_idempotency (idempotency_key, transaction_id)
  VALUES (p_idempotency_key, v_new_id);

  -- Audit log
  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (p_user_id, 'transaction_created', 'transactions', v_new_id,
          jsonb_build_object('amount', p_amount, 'type', p_type, 'tenant_id', p_tenant_id::TEXT));

  RETURN v_new_id;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4. MATERIALIZED VIEWS FOR REPORTING
-- ────────────────────────────────────────────────────────────

-- Daily tithe aggregation
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_daily_tithe_aggregation
AS
SELECT
  date_trunc('day', t.created_at)::DATE AS day,
  t.tenant_id,
  COUNT(*) AS transaction_count,
  SUM(t.amount) AS total_amount,
  SUM(t.platform_fee) AS total_platform_fee,
  COUNT(DISTINCT t.user_id) AS unique_members
FROM public.transactions t
WHERE t.category IN ('tithe', 'giving', 'offering')
  AND t.status = 'completed'
GROUP BY date_trunc('day', t.created_at)::DATE, t.tenant_id
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_tithe_agg
  ON public.mv_daily_tithe_aggregation(day, tenant_id);

-- Monthly church revenue
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_monthly_church_revenue
AS
SELECT
  date_trunc('month', t.created_at)::DATE AS month,
  t.tenant_id,
  t.category,
  COUNT(*) AS transaction_count,
  SUM(t.amount) AS total_amount,
  SUM(t.platform_fee) AS total_platform_fee,
  COUNT(DISTINCT t.user_id) AS unique_members
FROM public.transactions t
WHERE t.status = 'completed'
GROUP BY date_trunc('month', t.created_at)::DATE, t.tenant_id, t.category
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_revenue
  ON public.mv_monthly_church_revenue(month, tenant_id, category);

-- Platform-wide summary (superadmin dashboard)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_platform_summary
AS
SELECT
  COUNT(DISTINCT t.id) AS total_transactions,
  COALESCE(SUM(t.amount), 0) AS total_volume,
  COALESCE(SUM(t.platform_fee), 0) AS total_platform_fees,
  COUNT(DISTINCT t.tenant_id) AS active_tenants,
  COUNT(DISTINCT t.user_id) AS active_users,
  COALESCE(SUM(CASE WHEN t.category = 'tithe' THEN t.amount ELSE 0 END), 0) AS total_tithes,
  COALESCE(SUM(CASE WHEN t.category = 'giving' THEN t.amount ELSE 0 END), 0) AS total_givings,
  now() AS computed_at
FROM public.transactions t
WHERE t.status = 'completed'
  AND t.created_at > now() - interval '30 days'
WITH DATA;

-- Refresh function for materialized views
CREATE OR REPLACE FUNCTION public.refresh_reporting_views()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_daily_tithe_aggregation;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_church_revenue;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_platform_summary;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5. TENANT LEASE LIFECYCLE
-- ────────────────────────────────────────────────────────────

-- Ensure columns used by lease lifecycle exist
ALTER TABLE IF EXISTS public.tenants ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS quiz_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS quiz_lease_until TIMESTAMPTZ;

-- Extend church trial on approval
CREATE OR REPLACE FUNCTION public.extend_church_trial(p_church_id UUID, p_extra_days INTEGER DEFAULT 30)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_end TIMESTAMPTZ;
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.churches
  SET trial_ends_at = COALESCE(trial_ends_at, now()) + (p_extra_days || ' days')::interval,
      is_verified = true,
      verified_at = COALESCE(verified_at, now())
  WHERE id = p_church_id
  RETURNING trial_ends_at INTO v_new_end;

  -- Audit trail
  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'church_trial_extended', 'churches', p_church_id,
          jsonb_build_object('extra_days', p_extra_days, 'new_end', v_new_end::TEXT));

  RETURN v_new_end;
END;
$$;

-- Activate quiz lease with payment validation
DROP FUNCTION IF EXISTS public.activate_quiz_lease(UUID, TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.activate_quiz_lease(
  p_church_id UUID,
  p_payment_ref TEXT,
  p_duration_months INTEGER DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment_exists BOOLEAN;
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Validate payment reference exists in transactions
  SELECT EXISTS(
    SELECT 1 FROM public.transactions
    WHERE reference = p_payment_ref
      AND tenant_id = p_church_id
      AND status = 'completed'
  ) INTO v_payment_exists;

  IF NOT v_payment_exists THEN
    RAISE EXCEPTION 'Invalid or missing payment reference';
  END IF;

  -- Update churches table with quiz module access
  UPDATE public.churches
  SET quiz_enabled = true,
      quiz_lease_until = GREATEST(COALESCE(quiz_lease_until, now()), now()) + (p_duration_months || ' months')::interval
  WHERE id = p_church_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'quiz_lease_activated', 'churches', p_church_id,
          jsonb_build_object('payment_ref', p_payment_ref, 'duration_months', p_duration_months));

  RETURN true;
END;
$$;

-- Suspend a tenant account
CREATE OR REPLACE FUNCTION public.suspend_tenant(p_tenant_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.tenants
  SET is_active = false
  WHERE id = p_tenant_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_suspended', 'tenants', p_tenant_id,
          jsonb_build_object('reason', p_reason));

  RETURN true;
END;
$$;

-- Reactivate a tenant account
CREATE OR REPLACE FUNCTION public.reactivate_tenant(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.tenants
  SET is_active = true
  WHERE id = p_tenant_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_reactivated', 'tenants', p_tenant_id, '{}');

  RETURN true;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 6. PASTORAL CARE: PRAYER APPROVAL & TESTIMONY MODERATION
-- ────────────────────────────────────────────────────────────

ALTER TABLE IF EXISTS public.prayers
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS public.testimonies
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- ────────────────────────────────────────────────────────────
-- 7. VERIFY
-- ────────────────────────────────────────────────────────────
SELECT 'architecture_upgrade_complete' AS check;
