-- ═══════════════════════════════════════════════════════════════════════════
-- SOFT DELETE, SESSION TIMEOUT & RATE LIMITING FIXES
-- Adds deleted_at columns for soft-delete pattern
-- Adds session expiry enforcement
-- Wires up rate limiting for birthday email and database backup
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Add soft-delete columns
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 2. Create index for soft-delete queries
CREATE INDEX IF NOT EXISTS idx_profiles_deleted_at ON public.profiles (deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_churches_deleted_at ON public.churches (deleted_at) WHERE deleted_at IS NULL;

-- 3. Add session timeout: auto-deactivate sessions older than 7 days
CREATE OR REPLACE FUNCTION public.cleanup_expired_sessions()
RETURNS void
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_sessions
  SET is_active = false
  WHERE is_active = true
    AND updated_at < now() - interval '7 days';
END;
$$;

-- 4. Add session timeout: auto-expire login history older than 90 days
CREATE OR REPLACE FUNCTION public.cleanup_old_login_history()
RETURNS void
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.login_history
  WHERE created_at < now() - interval '90 days';
END;
$$;

-- 5. Rate limit function already exists from 20260707 migration (check_admin_rate_limit)
-- No action needed — just ensure the table exists below.

-- 6. Create admin_rate_limits table if not exists
CREATE TABLE IF NOT EXISTS public.admin_rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admin_rate_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin rate limits self" ON public.admin_rate_limits;
CREATE POLICY "Admin rate limits self"
  ON public.admin_rate_limits FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Admin rate limits read own" ON public.admin_rate_limits;
CREATE POLICY "Admin rate limits read own"
  ON public.admin_rate_limits FOR SELECT TO authenticated
  USING (auth.uid() = admin_id);

-- 7. Auto-cleanup rate limits older than 1 hour
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS void
SET search_path = public
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.admin_rate_limits
  WHERE created_at < now() - interval '1 hour';
END;
$$;
