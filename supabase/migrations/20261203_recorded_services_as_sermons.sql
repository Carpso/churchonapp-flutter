-- ============================================================================
-- 20261203_recorded_services_as_sermons.sql
-- Ended/archived live services become REAL sermon entries.
--
-- WHY: a finished livestream has a permanent recording (R2 `archive_url` or the
-- Cloudflare Stream HLS recording), but it was only reachable from the live
-- hub — never from the Sermons tab, and not searchable. Recordings ARE sermons.
--
-- FIX: materialise each ended/archived stream that has a playable URL into the
-- `sermons` table (category 'Recorded Service'), one row per stream via
-- `source_stream_id`. A trigger keeps it in sync as the archive lands, and a
-- backfill creates rows for already-ended services. Genuine (uploaded) sermons
-- are never duplicated: we skip when a sermon already points at the same media.
-- ============================================================================

-- 1) Link column + one-sermon-per-stream uniqueness (NULLs stay distinct).
ALTER TABLE public.sermons
  ADD COLUMN IF NOT EXISTS source_stream_id uuid REFERENCES public.live_streams(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_sermons_source_stream_id
  ON public.sermons (source_stream_id);

-- 2) Materialise / refresh the sermon for a recorded stream.
CREATE OR REPLACE FUNCTION public.sync_recorded_service(p_stream_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ls        record;
  v_url       text;
  v_church    text;
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

  -- Prefer the permanent R2 master; fall back to the Cloudflare recording HLS.
  v_url := COALESCE(NULLIF(btrim(v_ls.archive_url), ''), NULLIF(btrim(v_ls.hls_url), ''));
  IF v_url IS NULL THEN RETURN NULL; END IF;

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

  INSERT INTO public.sermons (
    title, preacher, speaker, description, thumbnail_url, video_url,
    category, is_live, church_id, viewer_count, duration_minutes,
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
    'Recorded Service', false, v_ls.church_id,
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
    cloudflare_video_id = COALESCE(EXCLUDED.cloudflare_video_id, sermons.cloudflare_video_id),
    duration_minutes = COALESCE(EXCLUDED.duration_minutes, sermons.duration_minutes),
    viewer_count = GREATEST(COALESCE(sermons.viewer_count, 0), COALESCE(EXCLUDED.viewer_count, 0))
  RETURNING id INTO v_sermon_id;

  RETURN v_sermon_id;
END;
$$;

-- 3) Trigger: keep the sermon row in sync as a stream ends / its archive lands.
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
  AFTER INSERT OR UPDATE OF status, archive_url, hls_url, thumbnail_url, ended_at, archived_at
  ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_recorded_service();

-- 4) Backfill already-ended services that have a playable recording.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT id FROM public.live_streams
     WHERE COALESCE(status, '') IN ('ended', 'archived')
       AND (COALESCE(btrim(archive_url), '') <> '' OR COALESCE(btrim(hls_url), '') <> '')
  LOOP
    PERFORM public.sync_recorded_service(r.id);
  END LOOP;
END $$;

REVOKE EXECUTE ON FUNCTION public.sync_recorded_service(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.trg_sync_recorded_service() FROM anon, public;
