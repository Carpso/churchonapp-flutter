-- ============================================================================
-- 20261244_weather_alert_candidates.sql
--
-- The single query the `weather-alerts` Edge Function uses to decide who to
-- evaluate. It lives in SQL rather than in the function for two reasons:
--
--   1. The user's LOCAL hour and LOCAL calendar date cannot be derived from a
--      lat/lng in application code. A user in Lusaka (UTC+2) must not be sent
--      a "quiet hours" breach at 01:00 UTC just because it is 03:00 in UTC.
--      Postgres computes it from the IANA timezone in one place, so every
--      user is evaluated against their own wall clock.
--
--   2. The once-per-day dedupe and the location fallback (user's own
--      coordinates, else their church's) are relational work. Doing it here
--      keeps the Edge Function to fetching and sending.
--
-- Returned local_hour / local_date / last_alert_on are what the function uses
-- for quiet hours, the service window and the dedupe claim.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.weather_alert_candidates()
RETURNS TABLE (
  user_id                uuid,
  tenant_id              text,
  lat                    double precision,
  lng                    double precision,
  label                  text,
  max_temp_c             numeric,
  min_temp_c             numeric,
  rain_probability_pct   numeric,
  max_wind_kph           numeric,
  window_start_hour      int,
  window_end_hour        int,
  quiet_start_hour       int,
  quiet_end_hour         int,
  local_hour             int,
  local_date             date,
  last_alert_on          date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH resolved AS (
    SELECT
      p.user_id,
      p.tenant_id,
      -- User's own saved point wins; otherwise the church they belong to.
      COALESCE(p.lat,  c.latitude)  AS lat,
      COALESCE(p.lng,  c.longitude) AS lng,
      COALESCE(p.location_label, c.name) AS label,
      p.max_temp_c, p.min_temp_c, p.rain_probability_pct, p.max_wind_kph,
      p.window_start_hour, p.window_end_hour,
      p.quiet_start_hour, p.quiet_end_hour,
      p.last_alert_on,
      -- Africa/Africa is the default because the primary market is Zambia and
      -- Zimbabwe; users outside it store an explicit timezone, which the
      -- client sends in `location_label`-adjacent metadata. Falling back keeps
      -- the function total rather than erroring.
      COALESCE(NULLIF(p.timezone, ''), 'Africa/Lusaka') AS tz
    FROM public.weather_alert_preferences p
    LEFT JOIN LATERAL (
      SELECT ch.latitude, ch.longitude, ch.name
        FROM public.churches ch
       WHERE ch.tenant_id::text = p.tenant_id
         AND ch.latitude IS NOT NULL
         AND ch.longitude IS NOT NULL
       LIMIT 1
    ) c ON TRUE
    WHERE p.enabled
      -- Only users who actually asked for something.
      AND (p.max_temp_c IS NOT NULL OR p.min_temp_c IS NOT NULL
        OR p.rain_probability_pct IS NOT NULL OR p.max_wind_kph IS NOT NULL)
  )
  SELECT
    r.user_id,
    r.tenant_id,
    r.lat,
    r.lng,
    r.label,
    r.max_temp_c, r.min_temp_c, r.rain_probability_pct, r.max_wind_kph,
    r.window_start_hour, r.window_end_hour,
    r.quiet_start_hour, r.quiet_end_hour,
    -- Local wall clock, per the user's own timezone.
    EXTRACT(HOUR  FROM now() AT TIME ZONE r.tz)::int AS local_hour,
    (now() AT TIME ZONE r.tz)::date                 AS local_date,
    r.last_alert_on
  FROM resolved r
  WHERE r.lat IS NOT NULL
    AND r.lng IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.weather_alert_candidates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.weather_alert_candidates() TO service_role;
