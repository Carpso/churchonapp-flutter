-- 20260922: NETWORK PROGRAMS — ministry schedules visible to connected churches
--
--  1. ministry_schedules SELECT: local tenant members already covered; extend
--     to churches the user has connected to (church_connections) so the
--     Bishop's network view can show other churches' programs.
--  2. get_connected_church_programs(p_limit): bounded RPC returning the next
--     upcoming program per connected church (1 per church, server-side).

-- 1. RLS: connected churches may view each other's ministry schedules (SELECT only)
DO $$ BEGIN
  DROP POLICY IF EXISTS "ministry_schedules: connected churches view" ON public.ministry_schedules;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
CREATE POLICY "ministry_schedules: connected churches view"
  ON public.ministry_schedules FOR SELECT
  TO authenticated
  USING (
    tenant_id IN (
      SELECT cc.connected_church_id
      FROM public.church_connections cc
      WHERE cc.user_id = auth.uid() AND cc.status IN ('pending', 'connected')
    )
  );

-- 2. RPC: next upcoming program for every church I've connected to
CREATE OR REPLACE FUNCTION public.get_connected_church_programs(p_limit INT DEFAULT 50)
RETURNS TABLE (
  church_id UUID,
  church_name TEXT,
  program_id UUID,
  ministry_name TEXT,
  scheduled_for DATE,
  start_time TIME,
  location TEXT,
  leader TEXT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT DISTINCT ON (ms.tenant_id)
    ms.tenant_id AS church_id,
    c.name AS church_name,
    ms.id AS program_id,
    ms.ministry_name,
    ms.scheduled_for,
    ms.start_time,
    ms.location,
    ms.leader
  FROM public.ministry_schedules ms
  JOIN public.church_connections cc ON cc.connected_church_id = ms.tenant_id
  JOIN public.churches c ON c.id = ms.tenant_id
  WHERE cc.user_id = auth.uid()
    AND cc.status IN ('pending', 'connected')
    AND ms.scheduled_for >= CURRENT_DATE
  ORDER BY ms.tenant_id, ms.scheduled_for ASC, ms.start_time ASC
  LIMIT GREATEST(1, p_limit);
$$;

REVOKE EXECUTE ON FUNCTION public.get_connected_church_programs(INT) FROM anon;