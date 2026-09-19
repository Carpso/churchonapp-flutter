-- ============================================================================
-- 20261200_live_stream_engagement.sql
-- Live-stream experience overhaul: real viewer presence/counts, ephemeral
-- on-air overlays (verse of the moment) + scrolling ticker, published over
-- Supabase Realtime so the viewer and the streamer stay in sync.
--
-- WHY:
--   * `stream_view_sessions` (20261121) recorded a start/end but NEVER updated
--     `live_streams.viewer_count`, so both the studio and the viewer polled a
--     column that was permanently 0/stale → "viewer count never moves".
--   * Overlays were written to `live_streams.overlay_*` but never read by the
--     viewer and never realtime, so no verse appeared on screen.
--   * There was no ticker transport at all.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Streamer-facing engagement columns on live_streams
-- ---------------------------------------------------------------------------
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS peak_viewer_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS ticker_message text;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS ticker_speed integer NOT NULL DEFAULT 40;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS ticker_enabled boolean NOT NULL DEFAULT true;

-- Public-safe, non-secret engagement columns (viewer counts / ticker / verse).
GRANT SELECT (
  peak_viewer_count, ticker_message, ticker_speed, ticker_enabled
) ON public.live_streams TO authenticated;

GRANT SELECT (
  peak_viewer_count, ticker_message, ticker_speed, ticker_enabled
) ON public.live_streams TO anon;

-- ---------------------------------------------------------------------------
-- 2) Viewer presence: heartbeat column on stream_view_sessions
-- ---------------------------------------------------------------------------
ALTER TABLE public.stream_view_sessions ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_svs_stream_live
  ON public.stream_view_sessions(stream_id) WHERE left_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3) Ephemeral on-air overlays (one row per active stream)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.live_stream_overlays (
  stream_id      uuid PRIMARY KEY REFERENCES public.live_streams(id) ON DELETE CASCADE,
  -- mirrors profiles.tenant_id (text) to avoid uuid-cast failures on legacy ids
  tenant_id      text,
  verse_text     text,
  verse_ref      text,
  ticker_message text,
  ticker_speed   integer NOT NULL DEFAULT 40,
  ticker_enabled boolean NOT NULL DEFAULT true,
  logo_url       text,
  updated_by     uuid,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.live_stream_overlays ENABLE ROW LEVEL SECURITY;

-- Anyone (incl. logged-out web viewers) may read the non-secret on-air overlay.
DROP POLICY IF EXISTS "Anyone reads stream overlays" ON public.live_stream_overlays;
CREATE POLICY "Anyone reads stream overlays" ON public.live_stream_overlays
  FOR SELECT TO anon, authenticated USING (true);

-- Only leadership of the owning church (or COA/superadmin) may publish.
DROP POLICY IF EXISTS "Leadership writes stream overlays" ON public.live_stream_overlays;
CREATE POLICY "Leadership writes stream overlays" ON public.live_stream_overlays
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin','super_admin','coa_employee','employee')
          OR (p.tenant_id IS NOT NULL
              AND p.tenant_id::text = live_stream_overlays.tenant_id::text
              AND p.role IN ('pastor','bishop','apostle','prophet','general_secretary',
                             'general_treasurer','treasurer','admin','leader','department_leader'))
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin','super_admin','coa_employee','employee')
          OR (p.tenant_id IS NOT NULL
              AND p.tenant_id::text = live_stream_overlays.tenant_id::text
              AND p.role IN ('pastor','bishop','apostle','prophet','general_secretary',
                             'general_treasurer','treasurer','admin','leader','department_leader'))
        )
    )
  );

GRANT SELECT ON public.live_stream_overlays TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.live_stream_overlays TO authenticated;

-- Realtime so the viewer picks up a verse/ticker change instantly.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
        AND tablename = 'live_stream_overlays'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.live_stream_overlays;
    END IF;
  END IF;
END $$;

ALTER TABLE public.live_stream_overlays REPLICA IDENTITY FULL;

-- ---------------------------------------------------------------------------
-- 4) Presence lifecycle RPCs
-- ---------------------------------------------------------------------------

-- Recompute the live count for a stream, expiring silent viewers. Server-side
-- single source of truth so the streamer and every viewer agree.
CREATE OR REPLACE FUNCTION public.stream_refresh_viewer_count(p_stream_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active integer := 0;
  v_peak   integer := 0;
BEGIN
  -- Expire viewers that stopped heart-beating (app backgrounded/killed).
  UPDATE stream_view_sessions
     SET left_at = now()
   WHERE stream_id = p_stream_id
     AND left_at IS NULL
     AND last_seen_at < now() - interval '90 seconds';

  SELECT count(*) INTO v_active
    FROM stream_view_sessions
   WHERE stream_id = p_stream_id
     AND left_at IS NULL
     AND last_seen_at >= now() - interval '90 seconds';

  UPDATE live_streams
     SET viewer_count = v_active,
         peak_viewer_count = GREATEST(COALESCE(peak_viewer_count, 0), v_active)
   WHERE id = p_stream_id
   RETURNING peak_viewer_count INTO v_peak;

  RETURN jsonb_build_object('count', v_active, 'peak', COALESCE(v_peak, v_active));
END;
$$;

-- Open a session, then immediately refresh the published count.
CREATE OR REPLACE FUNCTION public.stream_start_session(p_stream_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_tenant  uuid;
  v_session uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT church_id INTO v_tenant FROM live_streams WHERE id = p_stream_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stream not found';
  END IF;

  INSERT INTO stream_view_sessions (stream_id, tenant_id, user_id, last_seen_at)
  VALUES (p_stream_id, v_tenant, v_uid, now())
  RETURNING id INTO v_session;

  PERFORM stream_refresh_viewer_count(p_stream_id);
  RETURN v_session;
END;
$$;

-- Keep a session alive while the viewer is still watching.
CREATE OR REPLACE FUNCTION public.stream_viewer_heartbeat(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE stream_view_sessions
     SET last_seen_at = now()
   WHERE id = p_session_id
     AND user_id = auth.uid()
     AND left_at IS NULL;
END;
$$;

-- Close a session and republish the count.
CREATE OR REPLACE FUNCTION public.stream_end_session(p_session_id uuid, p_watched_seconds integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stream uuid;
BEGIN
  UPDATE stream_view_sessions
     SET left_at = now(),
         last_seen_at = now(),
         watched_seconds = GREATEST(COALESCE(p_watched_seconds, 0), 0)
   WHERE id = p_session_id
     AND user_id = auth.uid()
  RETURNING stream_id INTO v_stream;

  IF v_stream IS NOT NULL THEN
    PERFORM stream_refresh_viewer_count(v_stream);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.stream_refresh_viewer_count(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.stream_viewer_heartbeat(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.stream_start_session(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.stream_end_session(uuid, integer) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.stream_refresh_viewer_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stream_viewer_heartbeat(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stream_start_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stream_end_session(uuid, integer) TO authenticated;
