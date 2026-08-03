-- ════════════════════════════════════════════════════════════════
-- User Sessions Enhancement Migration
-- Adds device_name, is_current_session, and login trigger function
-- ════════════════════════════════════════════════════════════════

-- 1. Add new columns to user_sessions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema='public' AND table_name='user_sessions' AND column_name='device_name') THEN
        ALTER TABLE public.user_sessions ADD COLUMN device_name TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema='public' AND table_name='user_sessions' AND column_name='is_current_session') THEN
        ALTER TABLE public.user_sessions ADD COLUMN is_current_session BOOLEAN DEFAULT false;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema='public' AND table_name='user_sessions' AND column_name='user_agent') THEN
        ALTER TABLE public.user_sessions ADD COLUMN user_agent TEXT;
    END IF;
END $$;

-- 2. Create unique partial index to ensure only one current session per user
DROP INDEX IF EXISTS idx_user_sessions_current;
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_sessions_current 
    ON public.user_sessions(user_id) 
    WHERE is_current_session = true;

-- 3. Function to upsert user session on login (called from client or edge function)
CREATE OR REPLACE FUNCTION public.upsert_user_session(
    p_user_id UUID,
    p_device_name TEXT,
    p_ip_address TEXT,
    p_user_agent TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Mark all other sessions for this user as not current
    UPDATE public.user_sessions
    SET is_current_session = false,
        is_active = false
    WHERE user_id = p_user_id
      AND is_current_session = true;
    
    -- Insert or update the current session
    INSERT INTO public.user_sessions (
        user_id,
        device_name,
        ip_address,
        user_agent,
        last_active_at,
        is_active,
        is_current_session,
        created_at
    ) VALUES (
        p_user_id,
        p_device_name,
        p_ip_address,
        p_user_agent,
        now(),
        true,
        true,
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        device_name = EXCLUDED.device_name,
        ip_address = EXCLUDED.ip_address,
        user_agent = EXCLUDED.user_agent,
        last_active_at = now(),
        is_active = true,
        is_current_session = true;
        
    -- Auto-cleanup: keep only last 10 sessions per user
    DELETE FROM public.user_sessions
    WHERE user_id = p_user_id
      AND id NOT IN (
          SELECT id FROM public.user_sessions
          WHERE user_id = p_user_id
          ORDER BY last_active_at DESC
          LIMIT 10
      );
END;
$$;

-- 4. Function to mark a session as ended (logout)
CREATE OR REPLACE FUNCTION public.end_user_session(
    p_session_id UUID,
    p_user_id UUID
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.user_sessions
    SET is_active = false,
        is_current_session = false,
        last_active_at = now()
    WHERE id = p_session_id
      AND user_id = p_user_id;
END;
$$;

-- 5. Function to end all sessions except current
CREATE OR REPLACE FUNCTION public.end_all_other_sessions(
    p_user_id UUID,
    p_keep_session_id UUID
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.user_sessions
    SET is_active = false,
        is_current_session = false,
        last_active_at = now()
    WHERE user_id = p_user_id
      AND id != p_keep_session_id;
END;
$$;

-- 6. Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.upsert_user_session(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_user_session(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_all_other_sessions(UUID, UUID) TO authenticated;

-- 7. Add to realtime publication
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_rel pr
        JOIN pg_publication p ON p.oid = pr.prpubid
        WHERE p.pubname = 'supabase_realtime' 
        AND pr.prrelid = 'public.user_sessions'::regclass
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.user_sessions;
    END IF;
END $$;