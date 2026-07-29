-- Community Groups feature
-- Stores WhatsApp-style community groups for the Connect tab

CREATE TABLE IF NOT EXISTS community_communities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  banner_url TEXT,
  avatar_url TEXT,
  sort_order INT DEFAULT 0,
  tenant_id UUID REFERENCES churches(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES community_communities(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  subtitle TEXT,
  image_url TEXT,
  group_identifier TEXT NOT NULL,
  is_announcement BOOLEAN DEFAULT false,
  member_count INT DEFAULT 0,
  sort_order INT DEFAULT 0,
  tenant_id UUID REFERENCES churches(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: anyone in the church can read
ALTER TABLE community_communities ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_groups ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "community_communities_select" ON community_communities
    FOR SELECT USING (tenant_id IS NULL OR tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_groups_select" ON community_groups
    FOR SELECT USING (tenant_id IS NULL OR tenant_id::text = (SELECT tenant_id::text FROM profiles WHERE id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Admins can manage
DO $$ BEGIN
  CREATE POLICY "community_communities_insert" ON community_communities
    FOR INSERT WITH CHECK (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_communities_update" ON community_communities
    FOR UPDATE USING (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_communities_delete" ON community_communities
    FOR DELETE USING (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_groups_insert" ON community_groups
    FOR INSERT WITH CHECK (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_groups_update" ON community_groups
    FOR UPDATE USING (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin','pastor'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "community_groups_delete" ON community_groups
    FOR DELETE USING (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin','admin'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Seed with current hardcoded data (tenant_id NULL = visible to all churches)
INSERT INTO community_communities (id, name, description, banner_url, avatar_url, sort_order) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Central Hope Parish', 'Oversight, Announcements & Assemblies for Central Hope Parish.',
   'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800&q=80',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80', 0),
  ('a0000000-0000-0000-0000-000000000002', 'National Apostolic Network', 'Collective prayer, declarations, and congregation alignments across the country.',
   'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
   'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO community_groups (community_id, title, subtitle, image_url, group_identifier, is_announcement, member_count, sort_order) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'General Announcements', 'Whole parish announcements & alerts',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
   'general_grace', true, 154, 0),
  ('a0000000-0000-0000-0000-000000000001', 'Worship Team', 'Internal prep for Sunday missions',
   'https://images.unsplash.com/photo-1514525253361-b83f859b73c0?w=800&q=80',
   'worship-team-id', false, 12, 1),
  ('a0000000-0000-0000-0000-000000000001', 'Youth Ministry', 'Empowering the next generation',
   'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
   'youth_ministry', false, 47, 2),
  ('a0000000-0000-0000-0000-000000000002', 'Prayer Warriors', 'Collective intercession for the nation',
   'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
   'national-prayer-id', false, 89, 0),
  ('a0000000-0000-0000-0000-000000000002', 'Zambian Apostolic Network', 'Unity across 50+ congregations',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
   'apostolic-network-id', false, 312, 1),
  ('a0000000-0000-0000-0000-000000000002', 'Kingdom Youth Alliance', 'Cross-church youth empowerment',
   'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
   'youth-alliance-id', false, 98, 2)
ON CONFLICT DO NOTHING;
