-- ============================================================================
-- 20261139_community_network_create.sql
-- Communities & groups: real create/edit support.
-- Pastors Corner + Network Activity: allow leadership to actually POST.
--
-- WHY: the Connect → Communities tab had NO create path anywhere in the app
-- (`community_communities`/`community_groups` were reads only), so every church
-- showed "No groups available yet". Pastors Corner and Network Activity were
-- also read-only, so their screens were permanently empty. This migration:
--   * adds `created_by` + `updated_at` to communities/groups,
--   * lets any member create a community/group INSIDE their own church (while
--     leadership may manage any in the church), tenant-scoped,
--   * lets the creator edit/delete their own rows,
--   * fixes stale role lists (post-20260848 `employee` -> `coa_employee`) on
--     pastors_corner / network_activity and adds `created_by`.
-- ============================================================================

-- ── 1. Community / group columns ────────────────────────────────────────────
ALTER TABLE public.community_communities
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.community_groups
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE OR REPLACE FUNCTION public.touch_community_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_community_communities_touch ON public.community_communities;
CREATE TRIGGER trg_community_communities_touch
  BEFORE UPDATE ON public.community_communities
  FOR EACH ROW EXECUTE FUNCTION public.touch_community_updated_at();

DROP TRIGGER IF EXISTS trg_community_groups_touch ON public.community_groups;
CREATE TRIGGER trg_community_groups_touch
  BEFORE UPDATE ON public.community_groups
  FOR EACH ROW EXECUTE FUNCTION public.touch_community_updated_at();

-- ── 2. Community policies ───────────────────────────────────────────────────
DROP POLICY IF EXISTS "community_communities_insert" ON public.community_communities;
CREATE POLICY "community_communities_insert"
  ON public.community_communities FOR INSERT TO authenticated
  WITH CHECK (
    -- Any member may create a community in their OWN church.
    (created_by = auth.uid()
      AND tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid()))
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

DROP POLICY IF EXISTS "community_communities_update" ON public.community_communities;
CREATE POLICY "community_communities_update"
  ON public.community_communities FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::text = community_communities.tenant_id::text
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

DROP POLICY IF EXISTS "community_communities_delete" ON public.community_communities;
CREATE POLICY "community_communities_delete"
  ON public.community_communities FOR DELETE TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::text = community_communities.tenant_id::text
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

-- ── 3. Group policies ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "community_groups_insert" ON public.community_groups;
CREATE POLICY "community_groups_insert"
  ON public.community_groups FOR INSERT TO authenticated
  WITH CHECK (
    (created_by = auth.uid()
      AND tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid()))
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

DROP POLICY IF EXISTS "community_groups_update" ON public.community_groups;
CREATE POLICY "community_groups_update"
  ON public.community_groups FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::text = community_groups.tenant_id::text
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

DROP POLICY IF EXISTS "community_groups_delete" ON public.community_groups;
CREATE POLICY "community_groups_delete"
  ON public.community_groups FOR DELETE TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::text = community_groups.tenant_id::text
        AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                       'admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader')
    )
  );

-- ── 4. Pastors Corner: real posting by church leadership ────────────────────
ALTER TABLE public.pastors_corner
  ADD COLUMN IF NOT EXISTS created_by uuid;

DROP POLICY IF EXISTS "Pastors can create posts" ON public.pastors_corner;
CREATE POLICY "Pastors can create posts"
  ON public.pastors_corner FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::uuid = pastors_corner.church_id
        AND p.role IN ('pastor','bishop','apostle','prophet','general_secretary',
                       'admin','leader','department_leader',
                       'superadmin','super_admin','coa_employee','employee')
    )
  );

DROP POLICY IF EXISTS "Pastors can manage own posts" ON public.pastors_corner;
CREATE POLICY "Pastors can manage own posts"
  ON public.pastors_corner FOR ALL TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::uuid = pastors_corner.church_id
        AND p.role IN ('pastor','bishop','apostle','prophet','general_secretary',
                       'admin','leader','department_leader',
                       'superadmin','super_admin','coa_employee','employee')
    )
  );

-- ── 5. Network Activity: real posting by church leadership ──────────────────
ALTER TABLE public.network_activity
  ADD COLUMN IF NOT EXISTS created_by uuid;

DROP POLICY IF EXISTS "Churches can create activity" ON public.network_activity;
CREATE POLICY "Churches can create activity"
  ON public.network_activity FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id::uuid = network_activity.church_id
        AND p.role IN ('admin','pastor','bishop','apostle','prophet',
                       'general_secretary','leader','department_leader',
                       'superadmin','super_admin','coa_employee','employee')
    )
  );

-- ── 6. Seed a starter community + fellowship group for every church ─────────
-- Gives each church a real starting point (can be edited/removed by leaders).
-- NOTE: `community_communities.tenant_id` / `community_groups.tenant_id` FK to
-- `tenants(id)` (re-pointed from churches by migration 20260826), so we join
-- `tenants` to guarantee the FK holds.
INSERT INTO public.community_communities (name, description, sort_order, tenant_id)
SELECT 'Church Fellowship', 'Connect, share and grow together as a church family.',
       0, c.tenant_id
FROM public.churches c
JOIN public.tenants t ON t.id = c.tenant_id
WHERE c.tenant_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.community_communities x
    WHERE x.tenant_id = c.tenant_id
  );

INSERT INTO public.community_groups
  (community_id, title, subtitle, group_identifier, is_announcement, sort_order, tenant_id)
SELECT cc.id, 'General Fellowship', 'Everyone in the church',
       'general-' || replace(cc.id::text, '-', ''), true, 0, cc.tenant_id
FROM public.community_communities cc
WHERE NOT EXISTS (
    SELECT 1 FROM public.community_groups g WHERE g.community_id = cc.id
  );
