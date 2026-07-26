-- ════════════════════════════════════════════════════════════════
-- COA PAYMENTS CONSTRAINTS
-- Prevents duplicate payment submissions via unique payment_ref
-- ════════════════════════════════════════════════════════════════

-- Add unique constraint on payment_ref to prevent duplicate submissions
DO $$ BEGIN
    ALTER TABLE coa_payments ADD CONSTRAINT coa_payments_payment_ref_unique UNIQUE (payment_ref);
EXCEPTION WHEN duplicate_table OR duplicate_column THEN
    NULL;
END $$;

-- Add index for faster lookup when checking for existing payment refs
CREATE INDEX IF NOT EXISTS idx_coa_payments_payment_ref ON coa_payments (payment_ref);