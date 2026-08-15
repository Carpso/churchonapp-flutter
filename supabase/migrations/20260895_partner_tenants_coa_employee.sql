-- Partner onboarding is exposed to superadmins AND COA employees (the admin
-- hub shows the Manage Partners tile to both). The insert policy only allowed
-- 'superadmin'/'employee', so COA staff hitting "+" failed with an RLS error.

DROP POLICY IF EXISTS partner_tenants_insert ON partner_tenants;
DROP POLICY IF EXISTS partner_tenants_update ON partner_tenants;
DROP POLICY IF EXISTS partner_tenants_delete ON partner_tenants;
DROP POLICY IF EXISTS partner_offers_insert ON partner_offers;
DROP POLICY IF EXISTS partner_offers_update ON partner_offers;

CREATE POLICY partner_tenants_insert ON partner_tenants
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = ANY (ARRAY['superadmin', 'employee', 'coa_employee'])
    )
  );

CREATE POLICY partner_tenants_update ON partner_tenants
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = ANY (ARRAY['superadmin', 'employee', 'coa_employee'])
    )
  );

CREATE POLICY partner_tenants_delete ON partner_tenants
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = ANY (ARRAY['superadmin', 'employee', 'coa_employee'])
    )
  );

CREATE POLICY partner_offers_insert ON partner_offers
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = ANY (ARRAY['superadmin', 'employee', 'coa_employee'])
    )
  );

CREATE POLICY partner_offers_update ON partner_offers
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = ANY (ARRAY['superadmin', 'employee', 'coa_employee'])
    )
  );