-- ============================================================================
-- 20261209_live_stream_overlay_speaker.sql
-- Live-stream on-air overlay: SPEAKER details + editable CAPTION.
--
-- Extends the existing ephemeral `live_stream_overlays` table (20261200) which
-- already carries the verse + ticker and is published to every viewer over
-- Supabase Realtime. One row per stream; the studio upserts, the viewer reads.
--
--   speaker_name    -> e.g. "Pastor John Phiri"
--   speaker_title   -> e.g. "Senior Pastor" / "Guest Speaker"
--   speaker_church  -> e.g. "Rock of Ages, Kabulonga"
--   caption         -> short on-screen caption / sermon title (editorial, free
--                      text; distinct from live_streams.title)
-- ============================================================================

ALTER TABLE public.live_stream_overlays
  ADD COLUMN IF NOT EXISTS speaker_name   text,
  ADD COLUMN IF NOT EXISTS speaker_title  text,
  ADD COLUMN IF NOT EXISTS speaker_church text,
  ADD COLUMN IF NOT EXISTS caption        text;

COMMENT ON COLUMN public.live_stream_overlays.speaker_name IS
  'Name shown in the on-air speaker lower-third (realtime overlay).';
COMMENT ON COLUMN public.live_stream_overlays.speaker_title IS
  'Role/title of the speaker shown in the on-air lower-third.';
COMMENT ON COLUMN public.live_stream_overlays.speaker_church IS
  'Church/ministry of the speaker shown in the on-air lower-third.';
COMMENT ON COLUMN public.live_stream_overlays.caption IS
  'Short on-air caption/title (editable live by the streamer).';

-- Table-level SELECT is already granted to anon/authenticated and the table is
-- already in the supabase_realtime publication (20261200); no extra work needed.
