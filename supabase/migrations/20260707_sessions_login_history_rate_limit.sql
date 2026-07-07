-- 1. User Sessions Table
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_info TEXT,
    ip_address TEXT,
    last_active_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    is_active BOOLEAN DEFAULT true
);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own sessions" ON public.user_sessions;
CREATE POLICY "Users can view own sessions"
    ON public.user_sessions FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own sessions" ON public.user_sessions;
CREATE POLICY "Users can insert own sessions"
    ON public.user_sessions FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own sessions" ON public.user_sessions;
CREATE POLICY "Users can update own sessions"
    ON public.user_sessions FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own sessions" ON public.user_sessions;
CREATE POLICY "Users can delete own sessions"
    ON public.user_sessions FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all sessions" ON public.user_sessions;
CREATE POLICY "Admins can view all sessions"
    ON public.user_sessions FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND (role = 'superadmin' OR role = 'employee')
        )
    );

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON public.user_sessions(user_id, is_active) WHERE is_active = true;

-- 2. Login History Table
CREATE TABLE IF NOT EXISTS public.login_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ip_address TEXT,
    device_info TEXT,
    user_agent TEXT,
    location TEXT,
    status TEXT NOT NULL DEFAULT 'success',
    failure_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own login history" ON public.login_history;
CREATE POLICY "Users can view own login history"
    ON public.login_history FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service can insert login history" ON public.login_history;
CREATE POLICY "Service can insert login history"
    ON public.login_history FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all login history" ON public.login_history;
CREATE POLICY "Admins can view all login history"
    ON public.login_history FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND (role = 'superadmin' OR role = 'employee')
        )
    );

CREATE INDEX IF NOT EXISTS idx_login_history_user_id ON public.login_history(user_id);
CREATE INDEX IF NOT EXISTS idx_login_history_created_at ON public.login_history(created_at DESC);

-- 3. Rate Limiting Table for Admin Actions
CREATE TABLE IF NOT EXISTS public.admin_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    request_count INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admin_rate_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view own rate limits" ON public.admin_rate_limits;
CREATE POLICY "Admins can view own rate limits"
    ON public.admin_rate_limits FOR SELECT
    TO authenticated
    USING (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Service can insert rate limits" ON public.admin_rate_limits;
CREATE POLICY "Service can insert rate limits"
    ON public.admin_rate_limits FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Service can update rate limits" ON public.admin_rate_limits;
CREATE POLICY "Service can update rate limits"
    ON public.admin_rate_limits FOR UPDATE
    TO authenticated
    USING (auth.uid() = admin_id)
    WITH CHECK (auth.uid() = admin_id);

CREATE INDEX IF NOT EXISTS idx_admin_rate_limits_admin_action ON public.admin_rate_limits(admin_id, action_type);
CREATE INDEX IF NOT EXISTS idx_admin_rate_limits_window ON public.admin_rate_limits(window_start);

-- 4. Function to check rate limit
CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(
    p_admin_id UUID,
    p_action_type TEXT,
    p_max_requests INTEGER DEFAULT 30,
    p_window_minutes INTEGER DEFAULT 1
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_count INTEGER;
    recent_id UUID;
BEGIN
    -- Clean up old entries
    DELETE FROM public.admin_rate_limits
    WHERE window_start < now() - (p_window_minutes || ' minutes')::INTERVAL;

    -- Find an existing window for this admin + action within the time window
    SELECT id INTO recent_id
    FROM public.admin_rate_limits
    WHERE admin_id = p_admin_id
    AND action_type = p_action_type
    AND window_start > now() - (p_window_minutes || ' minutes')::INTERVAL
    LIMIT 1;

    IF recent_id IS NOT NULL THEN
        -- Update existing window count
        UPDATE public.admin_rate_limits
        SET request_count = request_count + 1
        WHERE id = recent_id
        RETURNING request_count INTO current_count;

        IF current_count > p_max_requests THEN
            RETURN false;
        END IF;
    ELSE
        -- Start a new window
        INSERT INTO public.admin_rate_limits (admin_id, action_type, request_count)
        VALUES (p_admin_id, p_action_type, 1);
    END IF;

    RETURN true;
END;
$$;

-- 5. Function to restrict role changes to superadmin/employee only
CREATE OR REPLACE FUNCTION public.check_role_change_permission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND (role = 'superadmin' OR role = 'employee')
        ) THEN
            RAISE EXCEPTION 'Only superadmins and employees can change roles';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_role_change ON public.profiles;
CREATE TRIGGER trg_profiles_role_change
    BEFORE UPDATE OF role ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.check_role_change_permission();

-- 6. Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'user_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE user_sessions;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'login_history'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE login_history;
  END IF;
END $$;
