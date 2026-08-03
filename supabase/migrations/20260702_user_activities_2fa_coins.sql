-- User Activities tracking
CREATE TABLE IF NOT EXISTS user_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  description TEXT NOT NULL,
  coins_earned INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_activities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own activities" ON user_activities;
CREATE POLICY "Users can view own activities" ON user_activities
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own activities" ON user_activities;
CREATE POLICY "Users can insert own activities" ON user_activities
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Add 2FA columns to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS totp_secret TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN DEFAULT false;

-- Add tenant_id to social_posts if not present
ALTER TABLE social_posts ADD COLUMN IF NOT EXISTS tenant_id TEXT;

CREATE INDEX IF NOT EXISTS idx_social_posts_tenant_id ON social_posts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_user_activities_user_id ON user_activities(user_id);

-- RPC function for adding coins
DROP FUNCTION IF EXISTS add_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION add_coins(user_id UUID, amount INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles SET coins = GREATEST(COALESCE(coins, 0) + amount, 0) WHERE id = user_id;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'user_activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE user_activities;
  END IF;
END $$;
