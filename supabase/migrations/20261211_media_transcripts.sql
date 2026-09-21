-- ============================================================================
-- 20261211_media_transcripts.sql
-- Whisper auto-transcription pipeline for Church On App.
--
-- Adds `media_transcripts`: one row per sermon OR per live-stream recording,
-- holding the Whisper transcript, WebVTT, timestamped segments, detected Bible
-- verse markers and a full-text search vector.
--
-- Server side only (Edge Function `transcribe-media`):
--   * rows are written by the service role  -> RLS is ON with NO write policy,
--   * every client write goes through the RPCs below (leadership-gated).
-- Tenant members may READ their tenant's transcripts (captions/subtitles need
-- it); platform staff may read everything; tenant_id IS NULL = global samples.
-- ============================================================================

BEGIN;

-- ── 1. Table ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.media_transcripts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid REFERENCES public.tenants(id) ON DELETE CASCADE,
  sermon_id        uuid REFERENCES public.sermons(id) ON DELETE CASCADE,
  live_stream_id   uuid REFERENCES public.live_streams(id) ON DELETE CASCADE,
  source_url       text NOT NULL,
  language         text,
  status           text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'processing', 'ready', 'failed')),
  error            text,
  transcript       text,
  vtt              text,
  segments         jsonb NOT NULL DEFAULT '[]'::jsonb,
  verse_markers    jsonb NOT NULL DEFAULT '[]'::jsonb,
  duration_seconds numeric,
  word_count       integer,
  -- Chunking bookkeeping so a sweep can resume a job that hit the wall clock.
  chunk_index      integer NOT NULL DEFAULT 0,
  chunk_total      integer NOT NULL DEFAULT 1,
  bytes_total      bigint,
  model            text,
  transcript_fts   tsvector,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_transcripts_target_check
    CHECK (sermon_id IS NOT NULL OR live_stream_id IS NOT NULL)
);

-- One transcript per target. Partial unique indexes (a transcript is keyed by
-- exactly one of the two columns, the other stays NULL).
CREATE UNIQUE INDEX IF NOT EXISTS ux_media_transcripts_sermon
  ON public.media_transcripts (sermon_id) WHERE sermon_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_media_transcripts_live_stream
  ON public.media_transcripts (live_stream_id) WHERE live_stream_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_media_transcripts_status
  ON public.media_transcripts (status);
CREATE INDEX IF NOT EXISTS idx_media_transcripts_tenant
  ON public.media_transcripts (tenant_id);
CREATE INDEX IF NOT EXISTS idx_media_transcripts_fts
  ON public.media_transcripts USING GIN (transcript_fts);
CREATE INDEX IF NOT EXISTS idx_media_transcripts_markers
  ON public.media_transcripts USING GIN (verse_markers jsonb_path_ops);

COMMENT ON TABLE public.media_transcripts IS
  'Whisper transcript (text + VTT + segments + verse markers) for a sermon or a live-stream recording.';
COMMENT ON COLUMN public.media_transcripts.chunk_index IS
  'Next audio chunk to transcribe (resume point for ?sweep=1).';

-- ── 2. Full-text search (vector column + trigger) ───────────────────────────
CREATE OR REPLACE FUNCTION public.media_transcripts_refresh()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.transcript_fts := to_tsvector(
    'english',
    COALESCE(NEW.transcript, '') || ' ' || COALESCE(NEW.vtt, '')
  );
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_media_transcripts_refresh ON public.media_transcripts;
CREATE TRIGGER trg_media_transcripts_refresh
BEFORE INSERT OR UPDATE ON public.media_transcripts
FOR EACH ROW EXECUTE FUNCTION public.media_transcripts_refresh();

REVOKE EXECUTE ON FUNCTION public.media_transcripts_refresh() FROM anon, public;

-- ── 3. RLS: read-only for clients, writes are service-role only ─────────────
ALTER TABLE public.media_transcripts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS media_transcripts_select ON public.media_transcripts;
CREATE POLICY media_transcripts_select ON public.media_transcripts
FOR SELECT TO authenticated
USING (
  public.is_platform_staff()
  OR tenant_id IS NULL
  OR tenant_id::text = public.get_my_tenant_id()
);
-- No INSERT / UPDATE / DELETE policy on purpose: only the service role (Edge
-- Function) or the SECURITY DEFINER RPCs below may write rows.

-- ── 4. Leadership gate helper ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_transcript_leader(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_platform_staff()
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND (p_tenant_id IS NULL OR p.tenant_id::text = p_tenant_id::text)
          AND p.role IN (
            'superadmin', 'super_admin', 'coa_employee', 'employee',
            'bishop', 'apostle', 'prophet', 'general_secretary',
            'general_treasurer', 'pastor', 'admin', 'leader',
            'department_leader', 'treasurer'
          )
      );
$$;

REVOKE EXECUTE ON FUNCTION public.is_transcript_leader(uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.is_transcript_leader(uuid) TO authenticated, service_role;

-- ── 5. request_transcription(target) ────────────────────────────────────────
-- Leadership-gated + idempotent: a ready/processing/pending transcript is
-- returned untouched; only a missing or failed one is (re)queued.
CREATE OR REPLACE FUNCTION public.request_transcription(
  p_sermon_id uuid DEFAULT NULL,
  p_live_stream_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant uuid;
  v_source text;
  v_row public.media_transcripts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_sermon_id IS NULL AND p_live_stream_id IS NULL THEN
    RAISE EXCEPTION 'target_required';
  END IF;

  IF p_sermon_id IS NOT NULL THEN
    SELECT COALESCE(s.tenant_id, c.tenant_id),
           COALESCE(
             NULLIF(btrim(s.audio_url), ''),
             NULLIF(btrim(s.archive_url), ''),
             NULLIF(btrim(s.video_url), '')
           )
      INTO v_tenant, v_source
      FROM public.sermons s
      LEFT JOIN public.churches c ON c.id = s.church_id
     WHERE s.id = p_sermon_id;
  ELSE
    SELECT c.tenant_id,
           COALESCE(
             NULLIF(btrim(l.archive_url), ''),
             NULLIF(btrim(l.hls_url), ''),
             NULLIF(btrim(l.stream_url), '')
           )
      INTO v_tenant, v_source
      FROM public.live_streams l
      LEFT JOIN public.churches c ON c.id = l.church_id
     WHERE l.id = p_live_stream_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'target_not_found';
  END IF;
  IF v_source IS NULL OR btrim(v_source) = '' THEN
    RAISE EXCEPTION 'no_media_source';
  END IF;
  IF NOT public.is_transcript_leader(v_tenant) THEN
    RAISE EXCEPTION 'leadership_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
    FROM public.media_transcripts
   WHERE (p_sermon_id IS NOT NULL AND sermon_id = p_sermon_id)
      OR (p_live_stream_id IS NOT NULL AND live_stream_id = p_live_stream_id)
   LIMIT 1;

  IF FOUND THEN
    IF v_row.status IN ('ready', 'processing', 'pending') THEN
      RETURN jsonb_build_object(
        'queued', false, 'status', v_row.status, 'transcript', to_jsonb(v_row));
    END IF;
    -- failed -> retry
    UPDATE public.media_transcripts
       SET status = 'pending', error = NULL, source_url = v_source,
           chunk_index = 0, chunk_total = 1, updated_at = now()
     WHERE id = v_row.id
     RETURNING * INTO v_row;
    RETURN jsonb_build_object(
      'queued', true, 'status', v_row.status, 'transcript', to_jsonb(v_row));
  END IF;

  INSERT INTO public.media_transcripts (
    tenant_id, sermon_id, live_stream_id, source_url, status
  ) VALUES (v_tenant, p_sermon_id, p_live_stream_id, v_source, 'pending')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'queued', true, 'status', v_row.status, 'transcript', to_jsonb(v_row));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_transcription(uuid, uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.request_transcription(uuid, uuid) TO authenticated, service_role;

-- ── 6. get_transcript(sermon_id | live_stream_id) ───────────────────────────
CREATE OR REPLACE FUNCTION public.get_transcript(
  p_sermon_id uuid DEFAULT NULL,
  p_live_stream_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.media_transcripts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_sermon_id IS NULL AND p_live_stream_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row
    FROM public.media_transcripts
   WHERE (p_sermon_id IS NOT NULL AND sermon_id = p_sermon_id)
      OR (p_live_stream_id IS NOT NULL AND live_stream_id = p_live_stream_id)
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_row.tenant_id IS NOT NULL
     AND NOT public.is_platform_staff()
     AND v_row.tenant_id::text <> COALESCE(public.get_my_tenant_id(), '') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  RETURN to_jsonb(v_row);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_transcript(uuid, uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.get_transcript(uuid, uuid) TO authenticated, service_role;

-- ── 7. set_transcript_verse_markers ─────────────────────────────────────────
-- The Edge Function runs as service role and writes markers directly; this RPC
-- exists so leadership can correct/curate markers from an admin surface.
CREATE OR REPLACE FUNCTION public.set_transcript_verse_markers(
  p_transcript_id uuid,
  p_markers jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant uuid;
  v_markers jsonb := COALESCE(p_markers, '[]'::jsonb);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF jsonb_typeof(v_markers) <> 'array' THEN
    RAISE EXCEPTION 'markers_must_be_array';
  END IF;

  SELECT tenant_id INTO v_tenant
    FROM public.media_transcripts WHERE id = p_transcript_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'transcript_not_found';
  END IF;
  IF NOT public.is_transcript_leader(v_tenant) THEN
    RAISE EXCEPTION 'leadership_required' USING ERRCODE = '42501';
  END IF;

  UPDATE public.media_transcripts
     SET verse_markers = v_markers, updated_at = now()
   WHERE id = p_transcript_id;

  RETURN jsonb_build_object('ok', true, 'count', jsonb_array_length(v_markers));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_transcript_verse_markers(uuid, jsonb) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.set_transcript_verse_markers(uuid, jsonb) TO authenticated, service_role;

-- ── 8. search_transcripts ───────────────────────────────────────────────────
-- Full-text search over ready transcripts, tenant-scoped, returning the matched
-- title + highlighted snippet + a start_seconds to seek to.
CREATE OR REPLACE FUNCTION public.search_transcripts(
  p_query text,
  p_limit integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_query tsquery;
  v_results jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_query IS NULL OR btrim(p_query) = '' THEN
    RETURN '[]'::jsonb;
  END IF;

  v_query := websearch_to_tsquery('english', p_query);

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
    INTO v_results
    FROM (
      SELECT
        mt.id,
        mt.sermon_id,
        mt.live_stream_id,
        mt.source_url,
        mt.language,
        mt.duration_seconds,
        COALESCE(s.title, ls.title, 'Recording') AS title,
        COALESCE(s.preacher, '') AS preacher,
        COALESCE(ls.archive_url, ls.hls_url, ls.stream_url, '') AS stream_url,
        ts_headline(
          'english',
          COALESCE(mt.transcript, ''),
          v_query,
          'StartSel=<<, StopSel=>>, MaxWords=30, MinWords=10'
        ) AS snippet,
        ts_rank(mt.transcript_fts, v_query) AS rank,
        COALESCE((mt.verse_markers -> 0 ->> 'start_seconds')::numeric, 0) AS start_seconds
      FROM public.media_transcripts mt
      LEFT JOIN public.sermons s ON s.id = mt.sermon_id
      LEFT JOIN public.live_streams ls ON ls.id = mt.live_stream_id
      WHERE mt.status = 'ready'
        AND (
          mt.tenant_id IS NULL
          OR public.is_platform_staff()
          OR mt.tenant_id::text = COALESCE(public.get_my_tenant_id(), '')
        )
        AND mt.transcript_fts @@ v_query
      ORDER BY rank DESC
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 50))
    ) t;

  RETURN v_results;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.search_transcripts(text, integer) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.search_transcripts(text, integer) TO authenticated, service_role;

COMMIT;
