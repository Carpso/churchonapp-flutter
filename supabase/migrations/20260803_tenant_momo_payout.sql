-- Per-tenant Mobile Money payout destination + collection method tracking.
-- The platform uses ONE Lipila merchant account (no per-tenant merchant ID).
-- Settlements always go to each church's registered MoMo number (payout_mobile).

ALTER TABLE churches ADD COLUMN IF NOT EXISTS payout_network TEXT NOT NULL DEFAULT 'mtn';
ALTER TABLE churches ADD COLUMN IF NOT EXISTS payout_mobile TEXT;

ALTER TABLE pending_payments ADD COLUMN IF NOT EXISTS method TEXT NOT NULL DEFAULT 'mobile_money';

-- Church leaders may update their own church's payout destination.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'churches' AND policyname = 'church_leaders_update_payout'
  ) THEN
    CREATE POLICY church_leaders_update_payout ON churches
      FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM profiles p
          WHERE p.id = auth.uid()
            AND p.tenant_id = churches.id
            AND p.role IN (
              'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
              'general_secretary', 'superadmin', 'employee', 'treasurer',
              'secretary', 'assistant_pastor'
            )
        )
      )
      WITH CHECK (true);
  END IF;
END $$;
