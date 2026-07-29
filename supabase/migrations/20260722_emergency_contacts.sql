CREATE TABLE IF NOT EXISTS emergency_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES churches(id) ON DELETE CASCADE,
  name text NOT NULL,
  phone text NOT NULL,
  icon text NOT NULL DEFAULT 'phone',
  category text NOT NULL DEFAULT 'emergency_service' CHECK (category IN ('emergency_service', 'church_contact')),
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;

DO $ BEGIN CREATE POLICY "emergency_contacts_select" ON emergency_contacts; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR SELECT USING (
    tenant_id IS NULL
    OR tenant_id = (
      SELECT id FROM churches
      WHERE id = emergency_contacts.tenant_id
    )
  );

DO $ BEGIN CREATE POLICY "emergency_contacts_insert" ON emergency_contacts; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR INSERT WITH CHECK (
    auth.jwt() ->> 'role' IN ('superadmin', 'admin', 'employee', 'coa_employee')
  );

DO $ BEGIN CREATE POLICY "emergency_contacts_update" ON emergency_contacts; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR UPDATE USING (
    auth.jwt() ->> 'role' IN ('superadmin', 'admin', 'employee', 'coa_employee')
  );

DO $ BEGIN CREATE POLICY "emergency_contacts_delete" ON emergency_contacts; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR DELETE USING (
    auth.jwt() ->> 'role' IN ('superadmin', 'admin', 'employee', 'coa_employee')
  );

-- Insert default global emergency contacts
INSERT INTO emergency_contacts (name, phone, icon, category, sort_order) VALUES
  ('Police', '911', 'shield', 'emergency_service', 1),
  ('Ambulance', '992', 'plusCircle', 'emergency_service', 2),
  ('Fire', '993', 'flame', 'emergency_service', 3)
ON CONFLICT DO NOTHING;
