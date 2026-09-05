-- 20261010 — Close anon/permissive message policies on public.messages
--
-- The live DB still carried legacy policies that let the anon role read and
-- INSERT messages without any auth check:
--   "Anyone can insert messages"
--   "Anyone can view messages"
-- These leak private chat between users to unauthenticated visitors and allow
-- anonymous spam. Secure SELECT/INSERT/UPDATE/DELETE are already provided by:
--   messages_select_auth (sender/receiver/user OR group membership)
--   messages_insert_auth (auth.uid() = sender_id OR user_id)
--   messages_update_auth (sender/receiver mark-as-read)
--   Users can delete own messages (user-scoped DELETE)
-- Deleting the permissive legacy policies is therefore safe.

DROP POLICY IF EXISTS "Anyone can insert messages" ON public.messages;
DROP POLICY IF EXISTS "Anyone can view messages" ON public.messages;