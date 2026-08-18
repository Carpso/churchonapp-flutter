-- 20260914 Live stream enhancements
-- WHIP ingest URL (phone-to-Cloudflare WebRTC) + viewer overlay metadata.

ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS whip_url text;
ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS overlay_verse text;
ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS overlay_verse_ref text;
ALTER TABLE live_streams ADD COLUMN IF NOT EXISTS overlay_logo_url text;

-- indexes for active stream lookups
CREATE INDEX IF NOT EXISTS live_streams_church_status_idx
  ON live_streams (church_id, status);