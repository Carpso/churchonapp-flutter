-- ═══════════════════════════════════════════════════════════════
-- COA PAYMENTS — Webhook support fixes
-- Expands CHECK constraint, adds missing columns for webhook processing
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- Expand CHECK constraint on status to include all valid webhook statuses
DO $$ BEGIN
    ALTER TABLE coa_payments DROP CONSTRAINT IF EXISTS coa_payments_status_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE coa_payments ADD CONSTRAINT coa_payments_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'settled', 'failed', 'completed', 'confirmed'));

-- Add missing columns for webhook processing
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'webhook_idempotency'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN webhook_idempotency TEXT UNIQUE;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'settled_at'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN settled_at TIMESTAMPTZ;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'phone_number'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN phone_number TEXT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'network'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN network TEXT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'category'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN category TEXT;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN metadata JSONB;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'coa_payments' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE coa_payments ADD COLUMN updated_at TIMESTAMPTZ;
    END IF;
END $$;

-- Index for faster webhook idempotency lookups
CREATE INDEX IF NOT EXISTS idx_coa_payments_webhook_idempotency ON coa_payments(webhook_idempotency);

-- Index for faster payment_ref lookups
CREATE INDEX IF NOT EXISTS idx_coa_payments_payment_ref ON coa_payments(payment_ref);

COMMIT;