-- ============================================================================
-- 20261141_stream_archive.sql
-- Live-stream recording archive (Cloudflare Stream -> Cloudflare R2).
--
-- WHY: Cloudflare Stream auto-records live services but only keeps them for the
-- plan retention window, and CF Stream is the playback layer, not an archive.
-- This adds the columns the `cloudflare-stream` Edge Function populates when a
-- leader archives a finished recording into R2 (the cheap master copy), so the
-- church always owns the source media — no VPS / external server required.
-- ============================================================================

ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS archive_url    text,
  ADD COLUMN IF NOT EXISTS archive_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS archive_error  text,
  ADD COLUMN IF NOT EXISTS archived_at    timestamptz;

-- archive_status: none | archiving | ready | failed
CREATE INDEX IF NOT EXISTS idx_live_streams_archive
  ON public.live_streams (archive_status)
  WHERE archive_status <> 'none';

COMMENT ON COLUMN public.live_streams.archive_url IS
  'Public R2 URL of the archived recording (master copy), set by cloudflare-stream archive_recording.';
