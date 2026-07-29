-- =============================================================================
-- Fix seed community groups + INSERT policy for public groups
-- =============================================================================

-- 0. Add is_public column if it doesn't exist
ALTER TABLE public.community_groups ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT true;

-- 1. Remove old seed groups (tenant_id IS NULL ones from the seed migration)
--    Only delete groups that have no members, to avoid breaking references
DELETE FROM public.community_groups
WHERE id IN (
  SELECT cg.id FROM public.community_groups cg
  WHERE cg.tenant_id IS NULL
  AND cg.community_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.community_group_members cgm
    WHERE cgm.group_id = cg.id
  )
);

-- 2. Re-insert with fixed, known UUIDs (public groups visible to all tenants)
INSERT INTO public.community_groups (id, community_id, title, subtitle, image_url, group_identifier, is_announcement, member_count, sort_order, is_public) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'General Announcements', 'Whole parish announcements & alerts',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
   'general_grace', true, 154, 0, true),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Worship Team', 'Internal prep for Sunday missions',
   'https://images.unsplash.com/photo-1514525253361-b83f859b73c0?w=800&q=80',
   'worship-team-id', false, 12, 1, true),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Youth Ministry', 'Empowering the next generation',
   'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
   'youth_ministry', false, 47, 2, true),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000002', 'Prayer Warriors', 'Collective intercession for the nation',
   'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
   'national-prayer-id', false, 89, 0, true),
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'Zambian Apostolic Network', 'Unity across 50+ congregations',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800&q=80',
   'apostolic-network-id', false, 312, 1, true),
  ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'Kingdom Youth Alliance', 'Cross-church youth empowerment',
   'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
   'youth-alliance-id', false, 98, 2, true)
ON CONFLICT (id) DO NOTHING;

-- 3. Update INSERT policy to allow sending to public community groups without membership
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;
CREATE POLICY "Authenticated users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND (
      community_group_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.community_group_members cgm
        WHERE cgm.group_id = messages.community_group_id
        AND cgm.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM public.community_groups cg
        WHERE cg.id = messages.community_group_id
        AND cg.is_public = true
      )
    )
  );
