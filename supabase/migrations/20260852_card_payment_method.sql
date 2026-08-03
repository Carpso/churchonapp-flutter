-- Add payment_method column to transactions table
-- Cards are collection-only (no payout via card), MO is for both collection and payout

DO $$ BEGIN
  ALTER TABLE transactions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'momo';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- Add index for filtering by payment method
CREATE INDEX IF NOT EXISTS idx_transactions_payment_method ON transactions (payment_method);

-- Update receipt view to include payment_method
COMMENT ON COLUMN transactions.payment_method IS 'Payment method used: momo (mobile money) or card';
