-- ============================================================================
-- 20261202_sample_stream_posters.sql
-- Default poster art for streams/sermons that have no thumbnail.
--
-- WHY: sample/creation flows left `thumbnail_url` NULL, so the Sermons tab and
-- the live-stream lists rendered blank/grey tiles. We seed tasteful FREE public
-- images (Unsplash URLs — no bundled binaries) as a fallback. The app ALSO
-- applies the same set client-side (`lib/core/config/sample_posters.dart`) for
-- any row created after this migration, so new content always has art.
-- ============================================================================

DO $$
DECLARE
  posters text[] := ARRAY[
    'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1510133755869-79a639739569?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1507699622108-4be3abd695ad?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=1200&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=1200&q=80&auto=format&fit=crop'
  ];
  n integer := array_length(posters, 1);
BEGIN
  UPDATE public.sermons
     SET thumbnail_url = posters[(((hashtext(id::text)::bigint % n) + n) % n)::int + 1]
   WHERE thumbnail_url IS NULL OR btrim(thumbnail_url) = '';

  UPDATE public.live_streams
     SET thumbnail_url = posters[(((hashtext(id::text)::bigint % n) + n) % n)::int + 1]
   WHERE thumbnail_url IS NULL OR btrim(thumbnail_url) = '';
END $$;
