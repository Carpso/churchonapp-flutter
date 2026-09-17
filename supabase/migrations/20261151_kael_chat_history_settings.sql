-- Kael AI chat history: order sessions by last activity and keep titles fresh.
-- ai_chat_sessions only had created_at, so the History view could not float the
-- most recently used conversation to the top. Add updated_at, keep it current
-- on every message, and index it for the ordered fetch.

ALTER TABLE IF EXISTS public.ai_chat_sessions
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Backfill from the newest message (or creation) for existing rows.
UPDATE public.ai_chat_sessions s
SET updated_at = COALESCE(
  (SELECT max(m.created_at) FROM public.ai_chat_messages m WHERE m.session_id = s.id),
  s.created_at,
  now()
)
WHERE s.updated_at IS NULL;

-- Any explicit session update (auto-title, rename) stamps updated_at.
CREATE OR REPLACE FUNCTION public.touch_ai_chat_sessions_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ai_chat_sessions_touch_updated_at ON public.ai_chat_sessions;
CREATE TRIGGER ai_chat_sessions_touch_updated_at
  BEFORE UPDATE ON public.ai_chat_sessions
  FOR EACH ROW EXECUTE FUNCTION public.touch_ai_chat_sessions_updated_at();

-- A new message bumps its parent session so History is activity-ordered.
CREATE OR REPLACE FUNCTION public.bump_ai_chat_session_on_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.ai_chat_sessions
    SET updated_at = now()
    WHERE id = NEW.session_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ai_chat_messages_bump_session ON public.ai_chat_messages;
CREATE TRIGGER ai_chat_messages_bump_session
  AFTER INSERT ON public.ai_chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.bump_ai_chat_session_on_message();

-- Trigger functions are never called directly.
REVOKE EXECUTE ON FUNCTION public.touch_ai_chat_sessions_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bump_ai_chat_session_on_message() FROM PUBLIC;

CREATE INDEX IF NOT EXISTS idx_ai_chat_sessions_user_updated
  ON public.ai_chat_sessions(user_id, updated_at DESC);
