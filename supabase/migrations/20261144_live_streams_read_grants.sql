-- ============================================================================
-- 20261144_live_streams_read_grants.sql
-- Fix `42501 permission denied for table live_streams` when starting a stream.
--
-- WHY: `20261109` replaced table-level SELECT with a narrow column allowlist.
-- The app does `.from('live_streams').insert({...}).select()` — `select()` is
-- `RETURNING *`, which requires SELECT on EVERY column, and `endStream` /
-- `_cleanupOldRecordings` read `cloudflare_stream_id` etc. Those columns were
-- not granted, so starting (and ending) a stream failed with 42501.
--
-- SECURITY: `live_streams_public_safe_read` lets ANY authenticated/anon user
-- read every row whose status is public, so `stream_key` / `rtmp_url` /
-- `whip_url` (the broadcast credentials) MUST stay ungranted. We therefore
-- GRANT SELECT only on the NON-secret columns the app needs.
-- ============================================================================

-- ── Authenticated: every column EXCEPT the three credentials ────────────────
GRANT SELECT (
  id, church_id, title, description, status,
  cloudflare_stream_id, stream_url,
  scheduled_at, started_at, ended_at, viewer_count,
  created_by, created_at, updated_at,
  streaming_backend, dash_url, preview_url,
  storage_bytes, storage_gb,
  hls_url, cloudflare_video_id,
  overlay_verse, overlay_verse_ref, overlay_logo_url,
  last_heartbeat,
  archive_url, archive_status, archive_error, archived_at,
  thumbnail_url, is_audio_only
) ON public.live_streams TO authenticated;

-- ── Anon: public-safe playback columns only ─────────────────────────────────
GRANT SELECT (
  id, church_id, title, description, status,
  scheduled_at, started_at, ended_at,
  hls_url, dash_url, preview_url, viewer_count, created_at,
  cloudflare_video_id, thumbnail_url, is_audio_only
) ON public.live_streams TO anon;

-- DML is already granted to authenticated; re-assert to be explicit/idempotent.
GRANT INSERT, UPDATE, DELETE ON public.live_streams TO authenticated;

-- ── Leadership-only credential access via a SECURITY DEFINER RPC ────────────
-- The Streaming Dashboard needs `stream_key`/`rtmp_url` to show OBS settings,
-- but those columns are deliberately not SELECT-granted. This RPC returns them
-- ONLY to leadership of the owning church (or COA/superadmin).
CREATE OR REPLACE FUNCTION public.get_my_stream_credentials(p_stream_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_role text;
  v_tid  text;
  v_row  public.live_streams%rowtype;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT role, tenant_id INTO v_role, v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_row FROM public.live_streams WHERE id = p_stream_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT (
    v_role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    OR (
      v_tid IS NOT NULL
      AND v_row.church_id::text = v_tid
      AND v_role IN ('pastor', 'bishop', 'apostle', 'prophet', 'general_secretary',
                     'general_treasurer', 'admin', 'leader', 'department_leader')
    )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authorised');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'stream_key', v_row.stream_key,
    'rtmp_url', v_row.rtmp_url,
    'hls_url', v_row.hls_url,
    'cloudflare_stream_id', v_row.cloudflare_stream_id,
    'status', v_row.status
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) TO authenticated;
