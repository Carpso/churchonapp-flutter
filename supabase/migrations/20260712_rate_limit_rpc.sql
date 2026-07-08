-- ═══════════════════════════════════════════════════════════════════════════════
-- RATE LIMIT RPC FUNCTION
-- Used by supabase/functions/_shared/rate-limit.ts for admin action throttling
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(
    p_admin_id UUID,
    p_action_type TEXT,
    p_max_requests INTEGER DEFAULT 30,
    p_window_minutes INTEGER DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
    v_allowed BOOLEAN;
BEGIN
    -- Clean old entries
    DELETE FROM public.admin_rate_limits
    WHERE created_at < now() - (p_window_minutes || ' minutes')::INTERVAL;

    -- Count recent requests
    SELECT COUNT(*) INTO v_count
    FROM public.admin_rate_limits
    WHERE admin_id = p_admin_id
      AND action_type = p_action_type
      AND created_at > now() - (p_window_minutes || ' minutes')::INTERVAL;

    v_allowed := v_count < p_max_requests;

    -- Record this attempt if allowed
    IF v_allowed THEN
        INSERT INTO public.admin_rate_limits (admin_id, action_type)
        VALUES (p_admin_id, p_action_type);
    END IF;

    RETURN v_allowed;
END;
$$;

-- Create tracking table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.admin_rate_limits (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for cleanup queries
CREATE INDEX IF NOT EXISTS idx_admin_rate_limits_lookup
    ON public.admin_rate_limits(admin_id, action_type, created_at DESC);

-- Auto-cleanup old entries
CREATE INDEX IF NOT EXISTS idx_admin_rate_limits_created
    ON public.admin_rate_limits(created_at);
