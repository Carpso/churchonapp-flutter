-- ============================================================================
-- 20261230_dead_unsplash_poster_cleanup.sql
-- Clear the dead sample-poster Unsplash URLs from EVERY table that can hold
-- them, so the app falls back to the branded in-Flutter poster
-- (SmartStreamPoster / BrandedStreamPoster) instead of requesting a 404.
--
-- WHY: these two Unsplash photos now return HTTP 404 (verified by HEAD):
--   * photo-1510133755869-79a639739569
--   * photo-1544427928-c49cdfebf4ad
-- `20261225_dead_sample_poster_cleanup.sql` only covered `sermons` and
-- `live_streams`; the same legacy URLs also linger in events, marketplace
-- items and klips, and rows still pointing at them trigger
-- `EncodingError: The source image cannot be decoded` wherever a raw
-- `AppImage(thumbnail_url)` is used.
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $$
DECLARE
  dead constant text[] := ARRAY[
    '%photo-1510133755869-79a639739569%',
    '%photo-1544427928-c49cdfebf4ad%'
  ];
  p text;
BEGIN
  -- sermons.thumbnail_url
  FOREACH p IN ARRAY dead LOOP
    UPDATE public.sermons SET thumbnail_url = NULL WHERE thumbnail_url LIKE p;
  END LOOP;

  -- live_streams.thumbnail_url
  FOREACH p IN ARRAY dead LOOP
    UPDATE public.live_streams SET thumbnail_url = NULL WHERE thumbnail_url LIKE p;
  END LOOP;

  -- events.image_url
  FOREACH p IN ARRAY dead LOOP
    UPDATE public.events SET image_url = NULL WHERE image_url LIKE p;
  END LOOP;

  -- klips.thumbnail_url (video_url is media, never a sample poster)
  IF to_regclass('public.klips') IS NOT NULL THEN
    FOREACH p IN ARRAY dead LOOP
      UPDATE public.klips SET thumbnail_url = NULL WHERE thumbnail_url LIKE p;
    END LOOP;
  END IF;

  -- marketplace_items.image (cast handles both text and jsonb columns)
  IF to_regclass('public.marketplace_items') IS NOT NULL THEN
    FOREACH p IN ARRAY dead LOOP
      UPDATE public.marketplace_items SET image = NULL WHERE image::text LIKE p;
    END LOOP;
  END IF;
END $$;
