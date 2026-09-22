-- ============================================================================
-- 20261217_events_special_guests.sql
-- The events feature ("Add Special Guest" in event_details_screen.dart) reads
-- and writes `events.special_guests` as a JSON array of {name, role, image_url},
-- but the column was never created on the `events` table -> every save 400'd
-- with "column events.special_guests does not exist".
-- Add the semantically-intended column (idempotent).
-- ============================================================================

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS special_guests JSONB DEFAULT '[]'::jsonb;

UPDATE public.events
  SET special_guests = '[]'::jsonb
  WHERE special_guests IS NULL;
