-- ════════════════════════════════════════════════════════════════
-- COA DIRECT PAYMENTS TABLE
-- Tracks payments made directly to COA MoMo (0976847775)
-- for app services like Business Meeting Pro Suite, Ads, Job Promos
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS coa_payments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  service_type  TEXT NOT NULL,  -- 'meeting_subscription', 'ad_promotion', 'job_promotion', etc.
  amount        NUMERIC(12,2) NOT NULL,
  payment_ref   TEXT NOT NULL,  -- user-submitted MoMo transaction ID
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_by   UUID REFERENCES profiles(id),
  approved_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Security: enable RLS
ALTER TABLE coa_payments ENABLE ROW LEVEL SECURITY;

-- Users can insert their own payments
DROP POLICY IF EXISTS "Users can insert own COA payments" ON coa_payments;
CREATE POLICY "Users can insert own COA payments"
  ON coa_payments FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Users can view their own payments
DROP POLICY IF EXISTS "Users can view own COA payments" ON coa_payments;
CREATE POLICY "Users can view own COA payments"
  ON coa_payments FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Superadmins can view all pending payments
DROP POLICY IF EXISTS "Superadmins can view all COA payments" ON coa_payments;
CREATE POLICY "Superadmins can view all COA payments"
  ON coa_payments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role = 'superadmin'
    )
  );

-- Superadmins can update (approve/reject) payments
DROP POLICY IF EXISTS "Superadmins can update COA payments" ON coa_payments;
CREATE POLICY "Superadmins can update COA payments"
  ON coa_payments FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role = 'superadmin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role = 'superadmin'
    )
  );
