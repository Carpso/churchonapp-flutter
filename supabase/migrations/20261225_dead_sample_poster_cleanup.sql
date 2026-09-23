-- ============================================================================
-- 20261225_dead_sample_poster_cleanup.sql
-- Clear dead sample-poster URLs seeded by 20261202_sample_stream_posters.sql.
--
-- WHY: two of the seven Unsplash sample posters now return HTTP 404
--   * photo-1510133755869-79a639739569  -> 404
--   * photo-1544427928-c49cdfebf4ad     -> 404
-- (both verified by HEAD request). Rows still pointing at them render
-- `EncodingError: The source image cannot be decoded` wherever a raw
-- `AppImage(thumbnail_url)` is used instead of `SmartStreamPoster`.
--
-- Setting them to NULL lets the app fall back to the branded in-Flutter
-- poster (SmartStreamPoster / BrandedStreamPoster) instead of fetching a
-- dead URL. Idempotent: safe to re-run.
-- ============================================================================

UPDATE public.sermons
   SET thumbnail_url = NULL
 WHERE thumbnail_url LIKE '%photo-1510133755869-79a639739569%'
    OR thumbnail_url LIKE '%photo-1544427928-c49cdfebf4ad%';

UPDATE public.live_streams
   SET thumbnail_url = NULL
 WHERE thumbnail_url LIKE '%photo-1510133755869-79a639739569%'
    OR thumbnail_url LIKE '%photo-1544427928-c49cdfebf4ad%';
