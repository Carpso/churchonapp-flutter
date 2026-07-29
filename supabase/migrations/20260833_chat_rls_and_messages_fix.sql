-- ============================================================
-- FIX MESSAGES TABLE: RLS Policies + user_id Column
-- ============================================================
-- Problems:
-- 1. "Authenticated users can send messages" policy has WITH CHECK (true)
--    → any user can insert messages as anyone
-- 2. messages_insert_auth requires auth.uid() = sender_id but chat_service
--    now also sends user_id column
-- 3. messages_update has no USING clause → broken
-- 4. user_id column may be NULL on old rows
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Drop the overly permissive "Authenticated users can send messages"
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;

-- ────────────────────────────────────────────────────────────
-- 2. Drop the old sender_id-only insert policy
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "messages_insert_auth" ON public.messages;

-- ────────────────────────────────────────────────────────────
-- 3. Create corrected INSERT policy
--    Accepts sender_id OR user_id matching auth.uid()
-- ────────────────────────────────────────────────────────────
CREATE POLICY "messages_insert_auth" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    OR auth.uid() = user_id
  );

-- ────────────────────────────────────────────────────────────
-- 4. Fix SELECT policy — allow sender, receiver, or group members
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "messages_select_auth" ON public.messages;
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;

CREATE POLICY "messages_select_auth" ON public.messages
  FOR SELECT TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR auth.uid() = user_id
    OR group_id IS NOT NULL
  );

-- ────────────────────────────────────────────────────────────
-- 5. Fix UPDATE policy — sender or receiver can update (mark as read)
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "messages_update_auth" ON public.messages;
DROP POLICY IF EXISTS "messages_update" ON public.messages;

CREATE POLICY "messages_update_auth" ON public.messages
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR auth.uid() = user_id
  );

-- ────────────────────────────────────────────────────────────
-- 6. Backfill user_id from sender_id for existing rows
-- ────────────────────────────────────────────────────────────
UPDATE public.messages
SET user_id = sender_id
WHERE user_id IS NULL AND sender_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- 7. Ensure user_id column exists with proper default
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.messages
  ALTER COLUMN user_id SET DEFAULT auth.uid();
