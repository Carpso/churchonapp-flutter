-- Community Groups: add is_public column + update RLS for church-specific groups

ALTER TABLE community_groups ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT true;
ALTER TABLE community_groups ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Update RLS policy to also allow public groups
DROP POLICY IF EXISTS "community_groups_select" ON community_groups;
CREATE POLICY "community_groups_select" ON community_groups
  FOR SELECT USING (
    is_public = true
    OR tenant_id IS NULL
    OR tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
  );

-- Allow church admins (pastor, bishop) to create groups for their church
DROP POLICY IF EXISTS "community_groups_insert" ON community_groups;
CREATE POLICY "community_groups_insert" ON community_groups
  FOR INSERT WITH CHECK (
    tenant_id IS NULL
    OR (
      tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
      AND EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop')
      )
    )
  );

DROP POLICY IF EXISTS "community_groups_update" ON community_groups;
CREATE POLICY "community_groups_update" ON community_groups
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop'))
  );

DROP POLICY IF EXISTS "community_groups_delete" ON community_groups;
CREATE POLICY "community_groups_delete" ON community_groups
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
  );

-- Same treatment for community_communities
ALTER TABLE community_communities ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT true;
ALTER TABLE community_communities ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

DROP POLICY IF EXISTS "community_communities_select" ON community_communities;
CREATE POLICY "community_communities_select" ON community_communities
  FOR SELECT USING (
    is_public = true
    OR tenant_id IS NULL
    OR tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "community_communities_insert" ON community_communities;
CREATE POLICY "community_communities_insert" ON community_communities
  FOR INSERT WITH CHECK (
    tenant_id IS NULL
    OR (
      tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid())
      AND EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop')
      )
    )
  );

DROP POLICY IF EXISTS "community_communities_update" ON community_communities;
CREATE POLICY "community_communities_update" ON community_communities
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor','bishop'))
  );

DROP POLICY IF EXISTS "community_communities_delete" ON community_communities;
CREATE POLICY "community_communities_delete" ON community_communities
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
  );

-- Update existing seed groups to be public (visible to all)
UPDATE community_groups SET is_public = true WHERE tenant_id IS NULL;
UPDATE community_communities SET is_public = true WHERE tenant_id IS NULL;
