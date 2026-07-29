CREATE TABLE IF NOT EXISTS klip_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  klip_id UUID NOT NULL REFERENCES klips(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, klip_id)
);

ALTER TABLE klip_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own klip likes"
  ON klip_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own klip likes"
  ON klip_likes FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can read their own klip likes"
  ON klip_likes FOR SELECT
  USING (auth.uid() = user_id);

CREATE INDEX idx_klip_likes_user ON klip_likes(user_id);
CREATE INDEX idx_klip_likes_klip ON klip_likes(klip_id);
