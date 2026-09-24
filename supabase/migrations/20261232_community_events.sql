-- 20261232: Community ↔ Event link table.
--
-- The Connect ▸ Communities hub had NO way to associate events with a
-- community (there was no join table at all), so any community-scoped events
-- view had nothing to read and threw. This adds a tenant-scoped join table
-- with RLS enabled — reads for the owning church/staff, writes (insert/delete)
-- restricted to church leadership. No `WITH CHECK (true)` anywhere.

CREATE TABLE IF NOT EXISTS public.community_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid NOT NULL REFERENCES public.community_communities(id) ON DELETE CASCADE,
  event_id     uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tenant_id    uuid REFERENCES public.tenants(id) ON DELETE CASCADE,
  created_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (community_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_community_events_community ON public.community_events(community_id);
CREATE INDEX IF NOT EXISTS idx_community_events_event ON public.community_events(event_id);
CREATE INDEX IF NOT EXISTS idx_community_events_tenant ON public.community_events(tenant_id);

ALTER TABLE public.community_events ENABLE ROW LEVEL SECURITY;

-- READ: same-church rows, global rows, or platform staff.
DROP POLICY IF EXISTS "community_events_select" ON public.community_events;
CREATE POLICY "community_events_select"
  ON public.community_events FOR SELECT TO authenticated
  USING (
    tenant_id IS NULL
    OR tenant_id::text = public.get_my_tenant_id()
    OR public.is_admin_or_employee()
  );

-- INSERT: the creator must be the caller, the row must belong to the caller's
-- church (or be global for staff), and the caller must be church leadership.
DROP POLICY IF EXISTS "community_events_insert" ON public.community_events;
CREATE POLICY "community_events_insert"
  ON public.community_events FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = created_by
    AND (tenant_id IS NULL OR tenant_id::text = public.get_my_tenant_id())
    AND (
      public.is_admin_or_employee()
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role IN (
            'pastor','bishop','apostle','prophet','general_secretary',
            'general_treasurer','treasurer','admin','leader','department_leader'
          )
      )
    )
  );

-- DELETE: creator, or leadership of the owning church / platform staff.
DROP POLICY IF EXISTS "community_events_delete" ON public.community_events;
CREATE POLICY "community_events_delete"
  ON public.community_events FOR DELETE TO authenticated
  USING (
    auth.uid() = created_by
    OR public.is_admin_or_employee()
    OR (tenant_id IS NOT NULL AND tenant_id::text = public.get_my_tenant_id())
  );

REVOKE ALL ON public.community_events FROM anon;
GRANT SELECT, INSERT, DELETE ON public.community_events TO authenticated;
