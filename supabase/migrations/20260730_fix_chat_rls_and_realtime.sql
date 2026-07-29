-- =============================================================================
-- Fix messages table: proper RLS policies + REPLICA IDENTITY for Realtime
-- =============================================================================

-- 1. Fix the broken SELECT policy (the previous migration had syntax errors:
--    "ON public; ... END$;.messages" which made the policy creation fail)
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
CREATE POLICY "Anyone can read messages" ON public.messages
    FOR SELECT TO authenticated
    USING (
        auth.uid()::text = user_id::text OR
        auth.uid()::text = receiver_id::text OR
        (group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id::text = messages.group_id::text AND gm.user_id::text = auth.uid()::text
        )) OR
        (community_group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.community_group_members cgm
            WHERE cgm.group_id::text = messages.community_group_id::text AND cgm.user_id::text = auth.uid()::text
        ))
    );

-- 2. Fix UPDATE policy to allow both sender AND receiver to update
--    (needed for reactions, read receipts, etc.)
DROP POLICY IF EXISTS "Users can update own messages" ON public.messages;
CREATE POLICY "Users can update own messages" ON public.messages
    FOR UPDATE TO authenticated
    USING (auth.uid()::text = user_id::text OR auth.uid()::text = receiver_id::text)
    WITH CHECK (auth.uid()::text = user_id::text OR auth.uid()::text = receiver_id::text);

-- 3. Enable REPLICA IDENTITY FULL on messages table so Realtime .stream()
--    properly captures UPDATE and DELETE changes (critical for reactions,
--    read receipts, soft-delete to appear live on other clients)
ALTER TABLE public.messages REPLICA IDENTITY FULL;
