CREATE TABLE IF NOT EXISTS baptisms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  name TEXT NOT NULL,
  date TIMESTAMPTZ DEFAULT now(),
  minister TEXT NOT NULL,
  location TEXT NOT NULL,
  status TEXT DEFAULT 'Pending',
  tenant_id TEXT,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  approved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ
);

ALTER TABLE baptisms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view baptisms in their tenant" ON "baptisms";
CREATE POLICY "Users can view baptisms in their tenant" ON "baptisms" FOR SELECT
  USING (
    tenant_id = (SELECT tenant_id FROM profiles WHERE id = auth.uid())
    OR auth.uid() IN (SELECT id FROM profiles WHERE role = 'superadmin')
  );

DROP POLICY IF EXISTS "Users can insert baptisms" ON "baptisms";
CREATE POLICY "Users can insert baptisms" ON "baptisms" FOR INSERT
  WITH CHECK (
    auth.uid() = created_by
    AND (
      tenant_id = (SELECT tenant_id FROM profiles WHERE id = auth.uid())
      OR auth.uid() IN (SELECT id FROM profiles WHERE role = 'superadmin')
    )
  );

DROP POLICY IF EXISTS "Admins can update baptisms in their tenant" ON "baptisms";
CREATE POLICY "Admins can update baptisms in their tenant" ON "baptisms" FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
        AND tenant_id = baptisms.tenant_id
        AND role IN ('admin', 'pastor', 'bishop', 'superadmin', 'prophet', 'apostle', 'leader')
    )
    OR auth.uid() IN (SELECT id FROM profiles WHERE role = 'superadmin')
  );
