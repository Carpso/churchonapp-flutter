-- ============================================================================
-- 20261226_worship_setlists.sql
-- Create the missing `public.worship_setlists` table.
--
-- ROOT CAUSE: the Flutter worship feature (lyrics_service.dart) reads/writes
-- `worship_setlists` via `.stream()` (initial REST GET
--   GET /rest/v1/worship_setlists?select=*&tenant_id=eq.<id>&order=created_at.desc
-- ) but the table was never created -> PostgREST 404 on every open.
--
-- The sibling song-lyrics table already exists under a DIFFERENT name
-- (`public.worship_lyrics`, created by 20260723 + extended by 20260840/20261150)
-- and MUST NOT be duplicated. Setlists are a separate concept: a named service
-- ordered list that references `worship_lyrics.id` values in `song_ids`.
--
-- Client contract (exact columns expected):
--   SELECT : id, title, song_ids, service_date, tenant_id, created_by, created_at
--   FILTER : tenant_id = <tenant>
--   ORDER  : created_at DESC
--   INSERT : title, song_ids, service_date, tenant_id, created_by
--   UPDATE : song_ids            (and updated_at)
--   DELETE : by id
--
-- NOTE: the client stores the ordered songs as a `song_ids` uuid[] array on the
-- parent row; it does NOT use a child items table, so no
-- `worship_setlist_items` is created here (avoids dead schema).
-- ============================================================================

-- ── 1. Table ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.worship_setlists (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  title        text NOT NULL,
  song_ids     uuid[] NOT NULL DEFAULT '{}'::uuid[],
  service_date date,
  notes        text,
  created_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- ── 2. Indexes ──────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_worship_setlists_tenant
  ON public.worship_setlists (tenant_id);
CREATE INDEX IF NOT EXISTS idx_worship_setlists_tenant_created
  ON public.worship_setlists (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_worship_setlists_created_by
  ON public.worship_setlists (created_by);

-- ── 3. updated_at touch trigger ─────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_worship_setlists_updated_at ON public.worship_setlists;
CREATE TRIGGER trg_worship_setlists_updated_at
  BEFORE UPDATE ON public.worship_setlists
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ── 4. Leadership gate (reuses the worship leadership gate) ─────────────────
CREATE OR REPLACE FUNCTION public.can_manage_worship_setlists(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_manage_worship_lyrics(p_tenant_id);
$$;

REVOKE EXECUTE ON FUNCTION public.can_manage_worship_setlists(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_manage_worship_setlists(uuid) TO authenticated;

-- ── 5. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.worship_setlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "worship_setlists_read" ON public.worship_setlists;
DROP POLICY IF EXISTS "worship_setlists_insert" ON public.worship_setlists;
DROP POLICY IF EXISTS "worship_setlists_update" ON public.worship_setlists;
DROP POLICY IF EXISTS "worship_setlists_delete" ON public.worship_setlists;

-- Any member of the church may read its setlists; platform staff may read all.
CREATE POLICY "worship_setlists_read" ON public.worship_setlists
  FOR SELECT TO authenticated
  USING (
    public.is_admin_or_employee()
    OR tenant_id::text = public.get_my_tenant_id()
  );

-- Leadership-only writes (never WITH CHECK (true)).
CREATE POLICY "worship_setlists_insert" ON public.worship_setlists
  FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_worship_setlists(tenant_id));

CREATE POLICY "worship_setlists_update" ON public.worship_setlists
  FOR UPDATE TO authenticated
  USING (public.can_manage_worship_setlists(tenant_id))
  WITH CHECK (public.can_manage_worship_setlists(tenant_id));

CREATE POLICY "worship_setlists_delete" ON public.worship_setlists
  FOR DELETE TO authenticated
  USING (public.can_manage_worship_setlists(tenant_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.worship_setlists TO authenticated;

-- ── 6. Realtime (the client uses .stream() for live setlist updates) ─────────
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.worship_setlists;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.worship_setlists REPLICA IDENTITY FULL;
