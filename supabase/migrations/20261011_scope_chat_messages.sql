-- 20261011 — Close anon leak + scope chat_messages policies
--
-- chat_messages is a private per-tenant chat table that still had:
--   "Anyone can insert messages"  (public role, WITH CHECK true)
--   "Anyone can view messages"    (public role, SELECT true)
-- i.e. any unauthenticated visitor could READ every private chat message and
-- inject spam. Replace with tenant-scoped authenticated policies:
--   SELECT  — same tenant as the message (profiles.tenant_id)
--   INSERT  — authenticated, and tenant_id matches the caller's tenant
-- The direct-message-era `messages` table was already fixed in 20261010; this
-- one is the room-based public.chat_messages table.

DROP POLICY IF EXISTS "Anyone can insert messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Anyone can view messages" ON public.chat_messages;

CREATE POLICY "chat_messages_select_auth"
  ON public.chat_messages FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NULL
    OR tenant_id::text = (
      SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "chat_messages_insert_auth"
  ON public.chat_messages FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      tenant_id IS NULL
      OR tenant_id::text = (
        SELECT tenant_id::text FROM public.profiles WHERE id = auth.uid()
      )
    )
  );