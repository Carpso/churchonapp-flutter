-- =============================================================================
-- Fix recursive RLS policy references and broken columns on messages
-- =============================================================================

-- Drop the broken select policy referencing sender_id
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;

-- Re-create the select policy using user_id (the correct column name)
DO $$ BEGIN CREATE POLICY "Anyone can read messages" ON public.messages
    FOR SELECT TO authenticated
    USING (
        auth.uid()::text = user_id::text OR
        auth.uid()::text = receiver_id::text OR
        (group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id::text = messages.group_id::text AND gm.user_id::text = auth.uid()::text
        ))
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
