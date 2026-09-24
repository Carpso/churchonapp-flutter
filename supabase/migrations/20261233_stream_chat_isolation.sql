-- 20261233 — Per-broadcast chat isolation for live_chat_messages
--
-- BUG: the viewer chat (`live_chat_service.dart` / `live_stream_screen.dart`)
-- read/wrote `live_chat_messages` filtered by `tenant_id` (the church), not by
-- the broadcast. Every stream at the same church therefore shared one chat, so
-- messages from an ENDED stream appeared in every NEW stream's chat.
--
-- Fix (server side):
--   1. Add `stream_id` (idempotent) so chat can be scoped to one broadcast.
--   2. Backfill legacy rows where a same-church stream window is derivable.
--   3. Index `(stream_id, created_at)` for the per-stream read.
--   4. Replace the blanket `USING (true)` policies with stream/church-scoped
--      ones (no `WITH CHECK (true)`).
--   5. Ensure the table is in the realtime publication (with REPLICA IDENTITY
--      FULL) so the client's stream-filtered channel receives inserts.

-- 1. stream_id column ---------------------------------------------------------
ALTER TABLE public.live_chat_messages
  ADD COLUMN IF NOT EXISTS stream_id UUID REFERENCES public.live_streams(id) ON DELETE CASCADE;

-- 2. Backfill: attach each legacy message to the church's most recent stream
--    that had started at/before the message (only where derivable) ------------
UPDATE public.live_chat_messages m
SET stream_id = (
  SELECT ls.id
  FROM public.live_streams ls
  WHERE (ls.church_id = m.church_id OR ls.church_id = m.tenant_id)
    AND COALESCE(ls.started_at, ls.scheduled_at, ls.created_at) <= m.created_at
  ORDER BY COALESCE(ls.started_at, ls.scheduled_at, ls.created_at) DESC
  LIMIT 1
)
WHERE m.stream_id IS NULL
  AND EXISTS (
    SELECT 1 FROM public.live_streams ls
    WHERE (ls.church_id = m.church_id OR ls.church_id = m.tenant_id)
      AND COALESCE(ls.started_at, ls.scheduled_at, ls.created_at) <= m.created_at
  );

-- 3. Index --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_live_chat_messages_stream_created
  ON public.live_chat_messages(stream_id, created_at);

-- 4. RLS: stream/church scoped (replaces the blanket authenticated policies) --
DROP POLICY IF EXISTS "Anyone can read live chat" ON public.live_chat_messages;
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.live_chat_messages;
DROP POLICY IF EXISTS "live_chat_select_stream" ON public.live_chat_messages;
DROP POLICY IF EXISTS "live_chat_insert_stream" ON public.live_chat_messages;

-- Read: a member may read chat for a stream belonging to their church (or a
-- platform-level stream); legacy unattached rows are visible only to their own
-- author (inert — the client always filters by stream_id).
CREATE POLICY "live_chat_select_stream" ON public.live_chat_messages
  FOR SELECT TO authenticated
  USING (
    (stream_id IS NULL AND user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.live_streams ls
      WHERE ls.id = live_chat_messages.stream_id
      AND (
        ls.church_id IS NULL
        OR ls.church_id::text = (
          SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
        )
      )
    )
  );

-- Insert: always the caller's own row, and only for a stream in their church
-- (or a platform-level stream). Never `WITH CHECK (true)`.
CREATE POLICY "live_chat_insert_stream" ON public.live_chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND stream_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      WHERE ls.id = live_chat_messages.stream_id
      AND (
        ls.church_id IS NULL
        OR ls.church_id::text = (
          SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
        )
      )
    )
  );

-- 5. Realtime publication + replica identity --------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'live_chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.live_chat_messages;
  END IF;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.live_chat_messages REPLICA IDENTITY FULL;
