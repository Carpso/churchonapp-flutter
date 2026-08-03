-- DM fixes: add receiver_id column (if missing), fix RLS for reactions

-- 1. Add receiver_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'messages' AND column_name = 'receiver_id'
  ) THEN
    ALTER TABLE messages ADD COLUMN receiver_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
    CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
  END IF;
END $$;

-- 2. Fix UPDATE policy: allow both sender AND receiver to update (for reactions)
DROP POLICY IF EXISTS "messages_update" ON messages;
DO $$
BEGIN
  CREATE POLICY "messages_update" ON messages
    FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = receiver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
