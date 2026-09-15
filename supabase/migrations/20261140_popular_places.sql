-- ============================================================================
-- 20261140_popular_places.sql
-- Popular drop-off / pickup gazetteer.
--
-- WHY: the map/ride data was only ever transaction records — there was no
-- derived "gazetteer" that learns frequently-used drop-off points and can
-- suggest them (as landmarks) to riders, couriers and delivery checkout. This
-- adds a nightly rollup over completed/accepted `ride_requests` +
-- `delivery_requests` (gridded to ~110 m), plus a proximity RPC the client
-- uses to suggest "frequently used" places.
--
-- Pure SQL + pg_cron. No external service / VPS.
-- ============================================================================

-- ── 1. Gazetteer table ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.popular_places (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_type       text NOT NULL DEFAULT 'dropoff',  -- dropoff | pickup
  grid_key         text NOT NULL,
  lat              double precision NOT NULL,
  lng              double precision NOT NULL,
  label            text,
  occurrence_count int NOT NULL DEFAULT 0,
  last_seen        timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (place_type, grid_key)
);

CREATE INDEX IF NOT EXISTS idx_popular_places_count
  ON public.popular_places (place_type, occurrence_count DESC);
CREATE INDEX IF NOT EXISTS idx_popular_places_geo
  ON public.popular_places (lat, lng);

ALTER TABLE public.popular_places ENABLE ROW LEVEL SECURITY;

-- Aggregated, non-PII: any signed-in user may read the gazetteer.
DROP POLICY IF EXISTS "popular_places_read" ON public.popular_places;
CREATE POLICY "popular_places_read"
  ON public.popular_places FOR SELECT TO authenticated
  USING (true);
-- Writes only via the SECURITY DEFINER rollup below.

-- ── 2. Nightly rollup ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rollup_popular_places(p_days int DEFAULT 180)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows int := 0;
  v_days int := GREATEST(COALESCE(p_days, 180), 1);
BEGIN
  -- Rebuild atomically (idempotent). A point must appear >= 2 times to qualify.
  DELETE FROM public.popular_places;

  WITH trips AS (
    SELECT dest_lat AS lat, dest_lng AS lng, created_at, 'dropoff' AS place_type
      FROM public.ride_requests
     WHERE dest_lat IS NOT NULL AND dest_lng IS NOT NULL
       AND created_at > now() - make_interval(days => v_days)
       AND status IN ('accepted','in_progress','arrived','completed','delivered','paid')
    UNION ALL
    SELECT dest_lat, dest_lng, created_at, 'dropoff'
      FROM public.delivery_requests
     WHERE dest_lat IS NOT NULL AND dest_lng IS NOT NULL
       AND created_at > now() - make_interval(days => v_days)
       AND status IN ('accepted','in_progress','arrived','completed','delivered','paid')
    UNION ALL
    SELECT pickup_lat, pickup_lng, created_at, 'pickup'
      FROM public.ride_requests
     WHERE pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL
       AND created_at > now() - make_interval(days => v_days)
       AND status IN ('accepted','in_progress','arrived','completed','delivered','paid')
    UNION ALL
    SELECT pickup_lat, pickup_lng, created_at, 'pickup'
      FROM public.delivery_requests
     WHERE pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL
       AND created_at > now() - make_interval(days => v_days)
       AND status IN ('accepted','in_progress','arrived','completed','delivered','paid')
  )
  INSERT INTO public.popular_places
    (place_type, grid_key, lat, lng, occurrence_count, last_seen, updated_at)
  SELECT place_type,
         place_type || ':' || round(lat::numeric, 3)::text || ':' ||
           round(lng::numeric, 3)::text,
         round(lat::numeric, 3)::double precision,
         round(lng::numeric, 3)::double precision,
         count(*),
         max(created_at),
         now()
    FROM trips
   GROUP BY place_type, round(lat::numeric, 3), round(lng::numeric, 3)
  HAVING count(*) >= 2;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rollup_popular_places(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.rollup_popular_places(int) FROM public;
REVOKE EXECUTE ON FUNCTION public.rollup_popular_places(int) FROM authenticated;

-- ── 3. Proximity lookup for the client ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_popular_places(
  p_lat    double precision DEFAULT NULL,
  p_lng    double precision DEFAULT NULL,
  p_limit  int DEFAULT 8,
  p_max_km numeric DEFAULT 50
)
RETURNS TABLE (
  id               uuid,
  place_type       text,
  lat              double precision,
  lng              double precision,
  label            text,
  occurrence_count int,
  distance_km      double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ranked AS (
    SELECT p.id, p.place_type, p.lat, p.lng, p.label, p.occurrence_count,
           CASE
             WHEN p_lat IS NULL OR p_lng IS NULL THEN NULL
             ELSE 6371 * acos(
               LEAST(1, GREATEST(-1,
                 sin(radians(p_lat)) * sin(radians(p.lat)) +
                 cos(radians(p_lat)) * cos(radians(p.lat)) *
                 cos(radians(p.lng) - radians(p_lng))
               ))
             )
           END AS distance_km
      FROM public.popular_places p
  )
  SELECT id, place_type, lat, lng, label, occurrence_count, distance_km
    FROM ranked
   WHERE distance_km IS NULL OR distance_km <= COALESCE(p_max_km, 50)
   ORDER BY (distance_km IS NULL), distance_km ASC, occurrence_count DESC
   LIMIT GREATEST(COALESCE(p_limit, 8), 1);
$$;

REVOKE EXECUTE ON FUNCTION public.get_popular_places(double precision, double precision, int, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_popular_places(double precision, double precision, int, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.get_popular_places(double precision, double precision, int, numeric) TO authenticated;

-- ── 4. Nightly cron (safe no-op without pg_cron) ────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('popular-places-rollup')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'popular-places-rollup');
    PERFORM cron.schedule(
      'popular-places-rollup',
      '40 2 * * *',
      $cron$SELECT public.rollup_popular_places(180);$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
