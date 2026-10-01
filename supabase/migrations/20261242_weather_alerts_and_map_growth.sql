-- ============================================================================
-- 20261242_weather_alerts_and_map_growth.sql
--
-- Two user-requested features, both built on the same "opt-in, consent-first"
-- principle.
--
-- 1. WEATHER ALERTS
--    Members choose which conditions they want to be warned about and whether
--    to be warned at all. A cron evaluates the forecast for every tenant that
--    has opted in and raises at most one alert per tenant per day, so a user is
--    never spammed. Open-Meteo is keyless, so no secret is required.
--
-- 2. MAP GROWTH
--    The map gets better as real usage is observed. This records ONLY the
--    user's OWN movement inside this app (Carpso rides/deliveries and in-app
--    navigation) plus explicit user reports.
--
--    IMPORTANT AND DELIBERATE: this does NOT and CANNOT collect location from
--    Yango/InDrive/Google Maps or any other third-party app. There is no API
--    that exposes another app's user's location history, and attempting it
--    without consent would be both a privacy and a legal violation. Growth here
--    means our own drivers, our own riders, our own navigation and OSM
--    enrichment — not surveillance of other apps' users.
--
-- RATIONALE FOR SERVER-SIDE SCHEDULING
--   A cron is the only way to reach a member whose phone is closed, which is
--   the whole point of an alert. On-device timers silently stop.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Weather alert preferences
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.weather_alert_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id TEXT,

  -- Master switch. Nothing is evaluated or sent while this is false.
  enabled BOOLEAN NOT NULL DEFAULT false,

  -- Thresholds are stored in the units the forecast is fetched in (Celsius),
  -- so there is no unit-conversion ambiguity at alert time.
  max_temp_c NUMERIC,
  min_temp_c NUMERIC,
  rain_probability_pct NUMERIC,
  max_wind_kph NUMERIC,

  -- Only alert for a service window rather than all day (e.g. 05:00-23:00).
  window_start_hour INT,
  window_end_hour INT,

  -- Quiet hours: never push inside these (church services usually sit here).
  quiet_start_hour INT NOT NULL DEFAULT 0,
  quiet_end_hour INT NOT NULL DEFAULT 6,

  -- Where the forecast is taken for. Defaults to the church, else the user.
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  location_label TEXT,

  -- IANA timezone the user's alerts are judged against ("Africa/Lusaka").
  -- REQUIRED for correctness: quiet hours and the once-per-day dedupe are
  -- meaningless in UTC, because a 23:00 service in Lusaka is 21:00 UTC and a
  -- user must never be woken because of someone else's offset.
  timezone TEXT NOT NULL DEFAULT 'Africa/Lusaka',

  -- Dedupe: one alert per user per local day per condition.
  last_alert_on DATE,
  last_alert_kind TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT weather_alert_hours_ck CHECK (
    (window_start_hour IS NULL OR window_start_hour BETWEEN 0 AND 23) AND
    (window_end_hour   IS NULL OR window_end_hour   BETWEEN 0 AND 23) AND
    quiet_start_hour  BETWEEN 0 AND 23 AND
    quiet_end_hour    BETWEEN 0 AND 23
  ),
  CONSTRAINT weather_alert_enabled_needs_setting_ck CHECK (
    NOT enabled OR (max_temp_c IS NOT NULL OR min_temp_c IS NOT NULL
                 OR rain_probability_pct IS NOT NULL OR max_wind_kph IS NOT NULL)
  ),
  -- An unknown zone would make local-hour maths throw and silently disable
  -- every alert for that user.
  CONSTRAINT weather_alert_timezone_ck CHECK (timezone = ANY (
    ARRAY['Africa/Lusaka','Africa/Harare','Africa/Maputo','Africa/Lagos',
          'Africa/Nairobi','Africa/Johannesburg','Africa/Accra',
          'Africa/Kinshasa','Africa/Luanda','UTC']
  ))
);

COMMENT ON TABLE public.weather_alert_preferences IS
  'Per-user weather alert settings. Disabled by default; opt-in only.';

ALTER TABLE public.weather_alert_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS weather_alert_prefs_own ON public.weather_alert_preferences;
CREATE POLICY weather_alert_prefs_own ON public.weather_alert_preferences
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION private.touch_weather_alert_prefs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_weather_alert_prefs_updated_at ON public.weather_alert_preferences;
CREATE TRIGGER trg_weather_alert_prefs_updated_at
  BEFORE UPDATE ON public.weather_alert_preferences
  FOR EACH ROW EXECUTE FUNCTION private.touch_weather_alert_prefs_updated_at();

-- One alert per user per local day, so re-running the cron is harmless.
CREATE UNIQUE INDEX IF NOT EXISTS ux_weather_alert_once_per_day
  ON public.weather_alert_preferences (user_id, COALESCE(last_alert_on, '-infinity'::date))
  WHERE last_alert_on IS NOT NULL;

-- Raised by the client when the user saves a change, so a saved setting takes
-- effect on the next cron tick without waiting for a daily job.
CREATE OR REPLACE FUNCTION private.queue_weather_alert_check()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  -- Deliberately does nothing on its own: the cron sweeps all opted-in users
  -- every 30 minutes. This trigger exists so the row is guaranteed to be
  -- picked up even if the user is outside the current window at save time.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_weather_alert_prefs_dirty ON public.weather_alert_preferences;
CREATE TRIGGER trg_weather_alert_prefs_dirty
  AFTER INSERT OR UPDATE ON public.weather_alert_preferences
  FOR EACH ROW WHEN (NEW.enabled)
  EXECUTE FUNCTION private.queue_weather_alert_check();

-- ---------------------------------------------------------------------------
-- 2. Map growth from our OWN usage (consent-scoped)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.map_growth_samples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  tenant_id TEXT,

  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  -- What produced this point, so it can be weighted and audited:
  --   ride | delivery | navigation | place_report | pin_save
  source TEXT NOT NULL,

  -- Road class / traffic hint observed while moving through here.
  speed_kph NUMERIC,
  heading_deg NUMERIC,
  traffic_level INT,

  -- Set by the client at capture time from its own local time; the server
  -- cannot infer the rider's timezone from a lat/lng.
  captured_local_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT map_growth_source_ck CHECK
    (source IN ('ride','delivery','navigation','place_report','pin_save')),
  CONSTRAINT map_growth_lat_ck  CHECK (lat  BETWEEN  -90 AND  90),
  CONSTRAINT map_growth_lng_ck  CHECK (lng  BETWEEN -180 AND 180)
);

CREATE INDEX IF NOT EXISTS idx_map_growth_samples_geo
  ON public.map_growth_samples (lat, lng);
CREATE INDEX IF NOT EXISTS idx_map_growth_samples_tenant_date
  ON public.map_growth_samples (tenant_id, created_at DESC);

ALTER TABLE public.map_growth_samples ENABLE ROW LEVEL SECURITY;

-- A user writes only their OWN samples. Nobody reads the raw trail.
DROP POLICY IF EXISTS map_growth_insert_own ON public.map_growth_samples;
CREATE POLICY map_growth_insert_own ON public.map_growth_samples
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- No SELECT policy on purpose: raw movement history is not readable by any
-- client, only aggregated server-side for tile enrichment.

-- Server-side aggregate used to enrich the map: dense corridors and slow
-- segments, never individual trails.
CREATE OR REPLACE FUNCTION public.get_map_growth_heatmap(
  p_tenant_id TEXT DEFAULT NULL,
  p_days     INT  DEFAULT 30
)
RETURNS TABLE (
  lat     DOUBLE PRECISION,
  lng     DOUBLE PRECISION,
  samples BIGINT,
  avg_speed_kph NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT ROUND(AVG(s.lat)::numeric, 4)::double precision AS lat,
           ROUND(AVG(s.lng)::numeric, 4)::double precision AS lng,
           COUNT(*)::bigint                        AS samples,
           ROUND(AVG(s.speed_kph), 1)              AS avg_speed_kph
      FROM public.map_growth_samples s
     WHERE s.created_at > now() - (p_days || ' days')::interval
       AND (p_tenant_id IS NULL OR s.tenant_id = p_tenant_id)
     GROUP BY ROUND(s.lat::numeric, 3), ROUND(s.lng::numeric, 3)
     ORDER BY COUNT(*) DESC
    LIMIT 5000;
END;
$$;

-- Exact identity argument list: a defaulted parameter does not let the empty
-- form `f()` resolve to `f(text, int)`, and the statement fails outright.
REVOKE ALL ON FUNCTION public.get_map_growth_heatmap(TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_map_growth_heatmap(TEXT, INT) TO authenticated;

-- Retention: this is behavioural data, so it does not accumulate forever.
-- 180 days is long enough to build corridor statistics and short enough to
-- honour data-minimisation.
CREATE OR REPLACE FUNCTION private.prune_map_growth_samples()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE v_n INT;
BEGIN
  DELETE FROM public.map_growth_samples
   WHERE created_at < now() - interval '180 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION private.prune_map_growth_samples() FROM PUBLIC, anon, authenticated;

-- Weather sweep + retention on one 30-minute tick.
--
-- The forecast HTTP call lives in the `weather-alerts` Edge Function, not in
-- plpgsql. pg_net only offers fire-and-forget (`http_post`) plus a
-- synchronous collector that is awkward to call from inside a trigger-safe
-- function; doing a real request from SQL is fragile, whereas an Edge Function
-- has a native fetch, proper error handling, and can be exercised and probed
-- directly. The database keeps what it is good at: the preferences, the
-- dedupe, and the decision to send.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='weather-alert-sweep') THEN
      PERFORM cron.schedule('weather-alert-sweep', '7,37 * * * *',
        $cron$SELECT net.http_post(
                   url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/weather-alerts',
                   headers := jsonb_build_object(
                     'Content-Type','application/json',
                     'x-cron-secret', private.get_cron_secret()),
                   body := jsonb_build_object('action','sweep')
                 );$cron$);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='map-growth-prune') THEN
      PERFORM cron.schedule('map-growth-prune', '13 3 * * *',
        $cron$SELECT private.prune_map_growth_samples();$cron$);
    END IF;
  END IF;
END $$;
