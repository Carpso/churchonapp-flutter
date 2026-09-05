-- 20261012 — Scope sermon_notes + stream_chat_messages to authenticated
--
-- sermon_notes and stream_chat_messages both had {public}-role policies:
--   sermon_notes_select   SELECT true   → anon could read every member's
--                                        private sermon notes as soon as any
--                                        exist (currently 0 rows, latent)
--   stream_chat_insert / select → anon (spam) read of live-stream chat
-- Replace with authenticated + ownership/tenant-scoped policies. verse_notes is
-- already auth-checked (qual auth.uid()=user_id) — no change needed.

DROP POLICY IF EXISTS sermon_notes_delete ON public.sermon_notes;
DROP POLICY IF EXISTS sermon_notes_insert ON public.sermon_notes;
DROP POLICY IF EXISTS sermon_notes_select ON public.sermon_notes;
DROP POLICY IF EXISTS sermon_notes_update ON public.sermon_notes;
DROP POLICY IF EXISTS "sermon_notes_select_auth" ON public.sermon_notes;
DROP POLICY IF EXISTS "sermon_notes_insert_auth" ON public.sermon_notes;
DROP POLICY IF EXISTS "sermon_notes_update_auth" ON public.sermon_notes;
DROP POLICY IF EXISTS "sermon_notes_delete_auth" ON public.sermon_notes;

CREATE POLICY "sermon_notes_select_auth" ON public.sermon_notes
  FOR SELECT TO authenticated
  USING (auth.uid() = author_id);

CREATE POLICY "sermon_notes_insert_auth" ON public.sermon_notes
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "sermon_notes_update_auth" ON public.sermon_notes
  FOR UPDATE TO authenticated
  USING (auth.uid() = author_id)
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "sermon_notes_delete_auth" ON public.sermon_notes
  FOR DELETE TO authenticated
  USING (auth.uid() = author_id);

DROP POLICY IF EXISTS stream_chat_insert ON public.stream_chat_messages;
DROP POLICY IF EXISTS stream_chat_select ON public.stream_chat_messages;
DROP POLICY IF EXISTS "stream_chat_select_auth" ON public.stream_chat_messages;
DROP POLICY IF EXISTS "stream_chat_insert_auth" ON public.stream_chat_messages;

-- stream_chat_messages has no tenant_id; scope via the owning live_streams row
-- (live_streams.church_id = profiles.tenant_id) OR platform-level streams.
CREATE POLICY "stream_chat_select_auth" ON public.stream_chat_messages
  FOR SELECT TO authenticated
  USING (
    stream_id IS NULL
    OR EXISTS (
      SELECT 1 FROM public.live_streams ls
      WHERE ls.id = stream_chat_messages.stream_id
      AND (
        ls.church_id IS NULL
        OR ls.church_id::text = (
          SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "stream_chat_insert_auth" ON public.stream_chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND (
      stream_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.live_streams ls
        WHERE ls.id = stream_chat_messages.stream_id
        AND (
          ls.church_id IS NULL
          OR ls.church_id::text = (
            SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
          )
        )
      )
    )
  );

-- stream_prayer_requests: same shape as stream_chat_messages — scope via the
-- owning live_streams row so only a member of the streaming church (or a
-- platform-level stream) can read/insert.
DROP POLICY IF EXISTS stream_prayer_insert ON public.stream_prayer_requests;
DROP POLICY IF EXISTS stream_prayer_select ON public.stream_prayer_requests;
DROP POLICY IF EXISTS stream_prayer_delete ON public.stream_prayer_requests;
DROP POLICY IF EXISTS "stream_prayer_select_auth" ON public.stream_prayer_requests;
DROP POLICY IF EXISTS "stream_prayer_insert_auth" ON public.stream_prayer_requests;
DROP POLICY IF EXISTS "stream_prayer_delete_auth" ON public.stream_prayer_requests;

CREATE POLICY "stream_prayer_select_auth" ON public.stream_prayer_requests
  FOR SELECT TO authenticated
  USING (
    stream_id IS NULL
    OR EXISTS (
      SELECT 1 FROM public.live_streams ls
      WHERE ls.id = stream_prayer_requests.stream_id
      AND (
        ls.church_id IS NULL
        OR ls.church_id::text = (
          SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "stream_prayer_insert_auth" ON public.stream_prayer_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND (
      stream_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.live_streams ls
        WHERE ls.id = stream_prayer_requests.stream_id
        AND (
          ls.church_id IS NULL
          OR ls.church_id::text = (
            SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
          )
        )
      )
    )
  );

CREATE POLICY "stream_prayer_delete_auth" ON public.stream_prayer_requests
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);