-- Standalone recreation of the AI chat tables (previously only defined inside
-- 20260710_missing_tables_schema.sql, which was part of a batch that failed to
-- apply). Kael chat is fully broken without these.
CREATE TABLE IF NOT EXISTS public.ai_chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_chat_sessions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
DROP POLICY IF EXISTS "Users can view own sessions" ON public.ai_chat_sessions;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can view own sessions" ON public.ai_chat_sessions
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DO $$ BEGIN
DROP POLICY IF EXISTS "Users can create own sessions" ON public.ai_chat_sessions;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can create own sessions" ON public.ai_chat_sessions
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DO $$ BEGIN
DROP POLICY IF EXISTS "Users can delete own sessions" ON public.ai_chat_sessions;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can delete own sessions" ON public.ai_chat_sessions
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_ai_chat_sessions_user ON public.ai_chat_sessions(user_id);

CREATE TABLE IF NOT EXISTS public.ai_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.ai_chat_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_chat_messages ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
DROP POLICY IF EXISTS "Users can view own messages" ON public.ai_chat_messages;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can view own messages" ON public.ai_chat_messages
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.ai_chat_sessions s WHERE s.id = ai_chat_messages.session_id AND s.user_id = auth.uid())
    );

DO $$ BEGIN
DROP POLICY IF EXISTS "Users can create messages in own sessions" ON public.ai_chat_messages;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can create messages in own sessions" ON public.ai_chat_messages
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.ai_chat_sessions s WHERE s.id = ai_chat_messages.session_id AND s.user_id = auth.uid())
    );

-- Needed by the regenerate flow (deletes the last assistant message).
DO $$ BEGIN
DROP POLICY IF EXISTS "Users can delete messages in own sessions" ON public.ai_chat_messages;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "Users can delete messages in own sessions" ON public.ai_chat_messages
    FOR DELETE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.ai_chat_sessions s WHERE s.id = ai_chat_messages.session_id AND s.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_session ON public.ai_chat_messages(session_id);
