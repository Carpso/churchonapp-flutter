-- Sermon R2 archive + Cloudflare Stream linkage.
--
-- Strategy: Cloudflare Stream is the PLAYBACK layer (adaptive-bitrate HLS, auto
-- thumbnail, DRY transcoding), while R2 keeps the cheap MASTER/archive copy of
-- the original upload (R2 storage is ~$0.015/GB with free egress).
-- `archive_url` holds the R2 master; `cloudflare_video_id` links the Stream
-- rendition so the asset can be re-created or deleted from Cloudflare.

ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS archive_url text;
ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS cloudflare_video_id text;

COMMENT ON COLUMN public.sermons.archive_url IS
  'R2 master/archive copy of the original source media (cheap long-term storage).';
COMMENT ON COLUMN public.sermons.cloudflare_video_id IS
  'Cloudflare Stream video UID for the adaptive-bitrate HLS rendition.';
