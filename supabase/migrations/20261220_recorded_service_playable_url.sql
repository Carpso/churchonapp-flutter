-- ============================================================================
-- 20261214_recorded_service_playable_url.sql
-- Recorded (ended/archived) services must materialise as sermons that PLAY.
--
-- ROOT CAUSE (fixed here): `20261203` copied `live_streams.hls_url` straight
-- into `sermons.video_url`/`archive_url`. But `hls_url` is the CLOUDFLARE
-- LIVE-INPUT manifest (`…/<live_input_uid>/manifest/video.m3u8`), which
-- Cloudflare only serves while the input is live. Once the broadcast ends it
-- answers HTTP 204 (verified live), so every player fails with
-- `manifestParsingError` / `MEDIA_ERR_NETWORK`.
--
-- The RECORDING is a separate Cloudflare *video* uid (generated when the
-- broadcast starts); only its own manifest keeps working. `cloudflare-stream`
-- now resolves + persists it as `live_streams.recording_hls_url`
-- (`resolve_recording` action, and opportunistically from the viewer-safe
-- `refresh_live_input`). This migration teaches the sync to USE it.
-- ============================================================================

-- 1) The recording's own HLS manifest (…/<video_uid>/manifest/video.m3u8).
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS recording_hls_url text;

COMMENT ON COLUMN public.live_streams.recording_hls_url IS
  'HLS manifest of the finished recording (its own Cloudflare video uid). Set by cloudflare-stream resolve_recording; safe to play after the live input goes idle.';

-- 2) Single source of truth for "what URL can a viewer actually play?".
--    Order: R2 master -> recorded video manifest -> derived from the video uid.
--    A dead live-input manifest is NEVER returned.
CREATE OR REPLACE FUNCTION public.playable_recording_url(p_ls public.live_streams)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  v := NULLIF(btrim(COALESCE(p_ls.archive_url, '')), '');
  IF v IS NOT NULL AND v ILIKE 'http%' AND v NOT ILIKE '%/null/%' THEN
    RETURN v;
  END IF;

  v := NULLIF(btrim(COALESCE(p_ls.recording_hls_url, '')), '');
  IF v IS NOT NULL AND v ILIKE 'http%' AND v NOT ILIKE '%/null/%' THEN
    RETURN v;
  END IF;

  -- Derive the recording manifest by swapping the live-input uid for the
  -- recording video uid in the stored URL.
  IF p_ls.cloudflare_video_id IS NOT NULL
     AND p_ls.cloudflare_stream_id IS NOT NULL
     AND p_ls.hls_url ILIKE '%' || p_ls.cloudflare_stream_id || '%' THEN
    v := replace(p_ls.hls_url, p_ls.cloudflare_stream_id, p_ls.cloudflare_video_id);
    IF v ILIKE 'http%' AND v NOT ILIKE '%/null/%' THEN
      RETURN v;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- 3) Materialise / refresh the sermon for a recorded stream.
CREATE OR REPLACE FUNCTION public.sync_recorded_service(p_stream_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ls        public.live_streams%ROWTYPE;
  v_url       text;
  v_church    text;
  v_tenant    uuid;
  v_existing  uuid;
  v_sermon_id uuid;
  posters     text[] := ARRAY[
    'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1510133755869-79a639739569?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1507699622108-4be3abd695ad?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=1200&q=80&auto=format&fit=crop'
  ];
  n integer := 7;
BEGIN
  SELECT * INTO v_ls FROM public.live_streams WHERE id = p_stream_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF COALESCE(v_ls.status, '') NOT IN ('ended', 'archived') THEN RETURN NULL; END IF;

  -- Only a URL that actually plays (R2 master or the recording's own manifest).
  v_url := public.playable_recording_url(v_ls);

  -- No playable recording => never publish a dead play button. Drop any row a
  -- previous (broken) sync created; it will be re-created automatically if a
  -- recording is resolved later (the trigger fires on recording_hls_url).
  IF v_url IS NULL THEN
    DELETE FROM public.sermons WHERE source_stream_id = p_stream_id;
    RETURN NULL;
  END IF;

  -- Never duplicate a genuine (uploaded) sermon for the same media.
  SELECT id INTO v_existing
    FROM public.sermons
   WHERE source_stream_id IS DISTINCT FROM p_stream_id
     AND (video_url = v_url OR archive_url = v_url)
   LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT name INTO v_church FROM public.churches WHERE id = v_ls.church_id;
  -- `live_streams.church_id` holds the tenant/church id; scope the sermon to it
  -- so tenant-filtered lists (Sermons tab) still surface the recording.
  SELECT id INTO v_tenant FROM public.tenants WHERE id = v_ls.church_id;

  INSERT INTO public.sermons (
    title, preacher, speaker, description, thumbnail_url, video_url,
    category, is_live, church_id, tenant_id, viewer_count, duration_minutes,
    created_at, archive_url, cloudflare_video_id, source_stream_id
  ) VALUES (
    COALESCE(NULLIF(btrim(v_ls.title), ''), 'Recorded Service'),
    COALESCE(NULLIF(btrim(v_church), ''), 'Church Service'),
    COALESCE(NULLIF(btrim(v_church), ''), 'Church Service'),
    COALESCE(v_ls.description, 'Recorded live service.'),
    COALESCE(
      NULLIF(btrim(v_ls.thumbnail_url), ''),
      posters[(((hashtext(p_stream_id::text)::bigint % n) + n) % n)::int + 1]
    ),
    v_url,
    'Recorded Service', false, v_ls.church_id, v_tenant,
    COALESCE(v_ls.viewer_count, 0),
    CASE
      WHEN v_ls.started_at IS NOT NULL AND v_ls.ended_at IS NOT NULL
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (v_ls.ended_at - v_ls.started_at)) / 60)::int)
      ELSE NULL
    END,
    COALESCE(v_ls.ended_at, v_ls.archived_at, v_ls.started_at, v_ls.created_at, now()),
    v_url,
    v_ls.cloudflare_video_id,
    p_stream_id
  )
  ON CONFLICT (source_stream_id) DO UPDATE SET
    title = EXCLUDED.title,
    preacher = EXCLUDED.preacher,
    speaker = EXCLUDED.speaker,
    description = EXCLUDED.description,
    thumbnail_url = COALESCE(NULLIF(btrim(sermons.thumbnail_url), ''), EXCLUDED.thumbnail_url),
    video_url = EXCLUDED.video_url,
    archive_url = EXCLUDED.archive_url,
    tenant_id = COALESCE(EXCLUDED.tenant_id, sermons.tenant_id),
    cloudflare_video_id = COALESCE(EXCLUDED.cloudflare_video_id, sermons.cloudflare_video_id),
    duration_minutes = COALESCE(EXCLUDED.duration_minutes, sermons.duration_minutes),
    viewer_count = GREATEST(COALESCE(sermons.viewer_count, 0), COALESCE(EXCLUDED.viewer_count, 0))
  RETURNING id INTO v_sermon_id;

  RETURN v_sermon_id;
END;
$$;

-- 4) Trigger: keep the sermon row in sync as a stream ends / a recording lands.
CREATE OR REPLACE FUNCTION public.trg_sync_recorded_service()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    PERFORM public.sync_recorded_service(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    -- Sermon bookkeeping must never break a stream write.
    NULL;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_live_stream_recorded_service ON public.live_streams;
CREATE TRIGGER trg_live_stream_recorded_service
  AFTER INSERT OR UPDATE OF status, archive_url, hls_url, thumbnail_url,
    ended_at, archived_at, recording_hls_url, cloudflare_video_id
  ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_recorded_service();

-- 5) BACKFILL: repair every already-materialised recorded sermon.
--    Streams with a playable source (R2 master, resolved recording manifest, or
--    a known recording video uid) get the correct URL; streams whose broadcast
--    was never recorded lose their dead sermon row (no unplayable play button).
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT id FROM public.live_streams
     WHERE COALESCE(status, '') IN ('ended', 'archived')
  LOOP
    BEGIN
      PERFORM public.sync_recorded_service(r.id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;

-- Belt-and-braces: drop any recorded sermon still pointing at a null/placeholder
-- URL whose stream has no playable source.
DELETE FROM public.sermons s
USING public.live_streams ls
WHERE s.source_stream_id = ls.id
  AND (s.video_url IS NULL
       OR btrim(s.video_url) = ''
       OR s.video_url ILIKE '%/null/%')
  AND public.playable_recording_url(ls) IS NULL;

REVOKE EXECUTE ON FUNCTION public.sync_recorded_service(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.trg_sync_recorded_service() FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.playable_recording_url(public.live_streams) FROM anon, public;
