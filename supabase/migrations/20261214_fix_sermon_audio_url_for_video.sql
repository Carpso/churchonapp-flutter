-- ============================================================================
-- 20261214_fix_sermon_audio_url_for_video.sql
--
-- ROOT CAUSE (video sermons played as AUDIO-ONLY):
--   `media_upload_screen.dart` wrote the fleet-wide `publicUrl` into BOTH the
--   `video_url` and `audio_url` columns for a VIDEO sermon:
--
--       'audio_url': _mediaType == 'audio' ? publicUrl : null,
--       'video_url': _mediaType == 'video' ? publicUrl : null,
--
--   For `_mediaType == 'video'` the row therefore ended up with a non-empty
--   `audio_url` pointing at the video (an R2 MP4 — which `just_audio` happily
--   plays — or a Cloudflare HLS `.m3u8`, which it cannot). The player had no
--   way to distinguish "really audio" from "video whose url was mirrored", and
--   more than one code path also picks `audio_url` when present.
--
--   The client is fixed (video uploads now write `audio_url = NULL`), but
--   EXISTING rows still carry the mirrored value and must be repaired.
--
-- FIX: clear `audio_url` whenever it duplicates `video_url` OR the row is a
--      video row (`video_url` is a Cloudflare HLS manifest or a non-audio
--      media file). Genuine audio sermons (audio_url set, video_url empty) are
--      left completely untouched. `archive_url` is deliberately NOT touched —
--      it is the R2 master copy and is never used as a playback source.
-- ============================================================================

-- 1) Exact mirror of video_url -> never a real audio track.
UPDATE public.sermons
   SET audio_url = NULL
 WHERE audio_url IS NOT NULL
   AND btrim(audio_url) <> ''
   AND btrim(audio_url) = btrim(coalesce(video_url, ''));

-- 2) video_url present + audio_url is a VIDEO container or HLS manifest
--    (mp4 / m3u8 / mov / webm / mkv / m4v) -> not an audio track.
UPDATE public.sermons
   SET audio_url = NULL
 WHERE audio_url IS NOT NULL
   AND btrim(audio_url) <> ''
   AND video_url IS NOT NULL
   AND btrim(video_url) <> ''
   AND (
     audio_url ILIKE '%.mp4'
     OR audio_url ILIKE '%.m4v'
     OR audio_url ILIKE '%.mov'
     OR audio_url ILIKE '%.webm'
     OR audio_url ILIKE '%.mkv'
     OR audio_url ILIKE '%.m3u8'
     OR audio_url ILIKE '%/manifest/video.m3u8%'
     OR audio_url ILIKE '%cloudflarestream.com%'
   );

-- 3) Guard the invariant for all future writes at the database level: an
--    `audio_url` may never equal `video_url`. A CHECK constraint cannot be
--    added safely over existing bad data, so it is added only after the
--    repairs above, and guarded so re-running the migration is a no-op.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sermons'::regclass
      AND conname = 'sermons_audio_url_not_video'
  ) THEN
    ALTER TABLE public.sermons
      ADD CONSTRAINT sermons_audio_url_not_video
      CHECK (
        audio_url IS NULL
        OR video_url IS NULL
        OR btrim(audio_url) = ''
        OR btrim(video_url) = ''
        OR btrim(audio_url) <> btrim(video_url)
      ) NOT VALID;
  END IF;
END $$;

COMMENT ON CONSTRAINT sermons_audio_url_not_video ON public.sermons IS
  'audio_url must never mirror video_url — a mirrored value makes the player treat a video sermon as audio-only.';
