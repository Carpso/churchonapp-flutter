-- Payment retry queue for reliability
-- Critical for Zambian internet conditions where connections drop frequently

CREATE TABLE IF NOT EXISTS payment_retry_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reference_id TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  recipient_phone TEXT NOT NULL,
  method TEXT NOT NULL DEFAULT 'momo',
  metadata JSONB DEFAULT '{}',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'resolved', 'failed', 'cancelled')),
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 5,
  next_retry_at TIMESTAMPTZ,
  last_attempt_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for efficient queue processing
CREATE INDEX idx_payment_retry_queue_pending
  ON payment_retry_queue (status, next_retry_at)
  WHERE status = 'pending';

-- RLS
ALTER TABLE payment_retry_queue ENABLE ROW LEVEL SECURITY;

DO $ BEGIN CREATE POLICY "payment_retry_queue_own" ON payment_retry_queue; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (auth.uid() = user_id);

DO $ BEGIN CREATE POLICY "payment_retry_queue_admin" ON payment_retry_queue; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin'))
  );

-- Auto-set user_id on insert
CREATE OR REPLACE FUNCTION set_payment_retry_user_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_payment_retry_insert
  BEFORE INSERT ON payment_retry_queue
  FOR EACH ROW
  EXECUTE FUNCTION set_payment_retry_user_id();
