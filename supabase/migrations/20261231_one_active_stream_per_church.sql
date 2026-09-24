-- 20261231 — ONE active live stream per church (tenant).
--
-- WHY: nothing stopped a church from having several `live_streams` rows with
-- status='live' at the same time (a second studio/OBS start, an app killed
-- mid-start leaving a stale row, a scheduled stream promoted while another is
-- live). Multiple live rows make the "which stream is the service?" question
-- unanswerable for viewers, keep burning Cloudflare minutes, and (after the
-- WHIP/WHEP playback fix) leave viewers pointed at the wrong broadcast.
--
-- This migration:
--   1) heals existing data by ending every live row except the newest per church,
--   2) enforces one live row per church with a partial UNIQUE index,
--   3) adds RPCs the client uses to offer a safe hand-off:
--        get_active_stream_for_church(p_church_id)      -> the live row or NULL
--        stop_other_streams(p_church_id, p_keep_id)     -> ends every other live row
--        start_stream_guard(p_church_id)                -> stop_other_streams(…, NULL)
--      `stop_other_streams` returns the stopped rows' `cloudflare_stream_id`s so
--      the client can DISABLE each Cloudflare live input (SQL cannot call the CF
--      API) — an ended row must not keep ingesting.

-- ── 1) Heal duplicates: keep the newest live row per church, end the rest ─────
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY church_id
           ORDER BY started_at DESC NULLS LAST, created_at DESC
         ) AS rn
  FROM public.live_streams
  WHERE status = 'live'
)
UPDATE public.live_streams ls
SET status = 'ended',
    ended_at = COALESCE(ls.ended_at, now())
FROM ranked r
WHERE ls.id = r.id
  AND r.rn > 1;

-- ── 2) One live row per church ────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS ux_live_streams_one_live_per_church
  ON public.live_streams (church_id)
  WHERE status = 'live';

-- ── 3a) Read the active stream for a church (viewer-safe) ─────────────────────
CREATE OR REPLACE FUNCTION public.get_active_stream_for_church(p_church_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row jsonb;
BEGIN
  IF p_church_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT to_jsonb(x) INTO v_row
  FROM (
    SELECT id, church_id, title, status, started_at, hls_url, preview_url,
           cloudflare_stream_id, cloudflare_video_id, is_audio_only,
           thumbnail_url, created_by
    FROM public.live_streams
    WHERE church_id = p_church_id
      AND status = 'live'
    ORDER BY started_at DESC NULLS LAST, created_at DESC
    LIMIT 1
  ) x;

  RETURN v_row;
END;
$function$;

-- ── 3b) End every OTHER live row for a church (+ report CF inputs to stop) ────
CREATE OR REPLACE FUNCTION public.stop_other_streams(p_church_id uuid, p_keep_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_own_tenant TEXT;
  v_staff BOOLEAN;
  v_stopped jsonb;
BEGIN
  IF p_church_id IS NULL THEN
    RAISE EXCEPTION 'church_required';
  END IF;

  -- Only the church's own leadership (or platform staff) may stop its streams.
  -- Role list mirrors the streaming gate (Edge Function + live_streams_manage).
  SELECT tenant_id::text INTO v_own_tenant
  FROM public.profiles
  WHERE id = auth.uid()
    AND role IN (
      'superadmin', 'coa_employee', 'pastor', 'bishop', 'admin', 'apostle',
      'prophet', 'general_secretary', 'general_treasurer', 'leader',
      'department_leader'
    );

  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee')
  ) INTO v_staff;

  IF NOT (v_staff OR (v_own_tenant IS NOT NULL AND v_own_tenant = p_church_id::text)) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  WITH upd AS (
    UPDATE public.live_streams
    SET status = 'ended',
        ended_at = COALESCE(ended_at, now())
    WHERE church_id = p_church_id
      AND status = 'live'
      AND (p_keep_id IS NULL OR id <> p_keep_id)
    RETURNING id, cloudflare_stream_id
  )
  SELECT COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id', id,
               'cloudflare_stream_id', cloudflare_stream_id
             )
           ),
           '[]'::jsonb
         )
  INTO v_stopped
  FROM upd;

  RETURN jsonb_build_object(
    'success', true,
    'stopped', v_stopped,
    'stopped_count', jsonb_array_length(v_stopped)
  );
END;
$function$;

-- ── 3c) Convenience alias used right before starting a new stream ─────────────
CREATE OR REPLACE FUNCTION public.start_stream_guard(p_church_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Ends any other live row for the church. The new stream is created AFTER
  -- this returns, so no `keep` id is needed.
  RETURN public.stop_other_streams(p_church_id, NULL);
END;
$function$;

-- ── 4) Grants: authenticated only (the RPCs self-gate on auth.uid()) ──────────
REVOKE EXECUTE ON FUNCTION public.get_active_stream_for_church(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.stop_other_streams(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.start_stream_guard(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_active_stream_for_church(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stop_other_streams(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_stream_guard(uuid) TO authenticated;
