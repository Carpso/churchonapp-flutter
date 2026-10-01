-- ═══════════════════════════════════════════════════════════════════════════
-- 20261238 — REAL MAP LOGISTICS: bus telemetry, traffic, parking, quick routes
-- ═══════════════════════════════════════════════════════════════════════════
-- WHY THIS FILE EXISTS
--   `church_buses`, `traffic_alerts`, `parking_zones` and `quick_routes` all
--   EXISTED but were unusable for a real map:
--     * none of them had latitude/longitude, so nothing could be plotted;
--     * LogisticsService returned HARDCODED Lusaka fixtures whenever a query
--       came back empty (a fake bus on Cairo Rd, fake "Heavy traffic", four
--       fake parking zones) — the app looked alive while showing fiction;
--     * there was no telemetry table, so a bus could not report where it is.
--
--   This adds geometry, telemetry and reporting so every value on the map is
--   real or ABSENT. No more silent fixture fallback (the client is changed to
--   return an honest empty list instead of Lusaka fiction).
--
-- TYPE NOTES (verified against live DB):
--   profiles.tenant_id = TEXT · churches.tenant_id = UUID
--   church_buses.church_id = UUID · church_buses.tenant_id = UUID
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. BUS TELEMETRY — a live GPS heartbeat per bus
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.bus_locations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_id         UUID NOT NULL REFERENCES public.church_buses(id) ON DELETE CASCADE,
  tenant_id      UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  lat            DOUBLE PRECISION NOT NULL,
  lng            DOUBLE PRECISION NOT NULL,
  heading        DOUBLE PRECISION,          -- degrees 0-360
  speed_kmh      DOUBLE PRECISION,
  recorded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_bus_locations_bus_time
  ON public.bus_locations (bus_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_bus_locations_tenant_time
  ON public.bus_locations (tenant_id, recorded_at DESC);

ALTER TABLE public.bus_locations ENABLE ROW LEVEL SECURITY;

-- A driver/leader posts their own bus ping; tenant staff read the fleet.
DO $$ BEGIN
  CREATE POLICY bus_locations_insert_own ON public.bus_locations
    FOR INSERT TO authenticated
    WITH CHECK (recorded_by = auth.uid()
                OR public.is_tenant_leadership()
                OR public.is_platform_staff());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY bus_locations_read_tenant ON public.bus_locations
    FOR SELECT TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id()
           OR public.is_platform_staff());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- The newest ping per bus in a tenant. SECURITY DEFINER so ordinary members
-- can watch a bus without needing write access.
CREATE OR REPLACE FUNCTION public.get_live_bus_positions(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'bus_id',      b.id,
    'name',        b.name,
    'route',       b.route,
    'is_active',   b.is_active,
    'eta',         b.eta,
    'next_stop',   b.next_stop,
    'lat',         l.lat,
    'lng',         l.lng,
    'heading',     l.heading,
    'speed_kmh',   l.speed_kmh,
    'recorded_at', l.recorded_at,
    -- A ping older than 3 minutes means the vehicle is not reporting.
    'stale',       (l.recorded_at IS NOT NULL
                     AND l.recorded_at < now() - interval '3 minutes')
  )), '[]'::jsonb)
    FROM public.church_buses b
    LEFT JOIN LATERAL (
      SELECT * FROM public.bus_locations bl
       WHERE bl.bus_id = b.id
       ORDER BY bl.recorded_at DESC
       LIMIT 1
    ) l ON TRUE
   WHERE b.tenant_id = p_tenant_id;
$$;

REVOKE ALL ON FUNCTION public.get_live_bus_positions(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_live_bus_positions(UUID)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. GEOMETRY + TRUTHFUL FIELDS on the four existing tables
-- ═══════════════════════════════════════════════════════════════════════════

-- 2a. Buses: live-position mirror + driver link.
ALTER TABLE public.church_buses
  ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS heading DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS speed_kmh DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_ping_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS driver_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_church_buses_tenant_active
  ON public.church_buses (tenant_id, is_active);

-- 2b. Traffic incidents need coordinates to be drawn at all.
ALTER TABLE public.traffic_alerts
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS radius_m INTEGER DEFAULT 500,
  ADD COLUMN IF NOT EXISTS reported_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_traffic_alerts_tenant_created
  ON public.traffic_alerts (tenant_id, created_at DESC);

ALTER TABLE public.traffic_alerts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY traffic_alerts_read_tenant ON public.traffic_alerts
    FOR SELECT TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id()
           OR public.is_platform_staff());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Any signed-in member may REPORT an incident (that is the crowd-sourcing).
DO $$ BEGIN
  CREATE POLICY traffic_alerts_report ON public.traffic_alerts
    FOR INSERT TO authenticated
    WITH CHECK (reported_by = auth.uid() OR reported_by IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2c. Parking needs a point or polygon and a real availability signal.
ALTER TABLE public.parking_zones
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS polygon JSONB,          -- [[lat,lng], ...]
  ADD COLUMN IF NOT EXISTS zone_type TEXT,          -- church|street|paid|overflow
  ADD COLUMN IF NOT EXISTS fee_kwacha NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_parking_zones_tenant ON public.parking_zones (tenant_id);

-- 2d. Quick routes: real origin/destination so the app can actually route them.
ALTER TABLE public.quick_routes
  ADD COLUMN IF NOT EXISTS from_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS from_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS from_label TEXT,
  ADD COLUMN IF NOT EXISTS to_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS to_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS to_label TEXT,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_quick_routes_tenant ON public.quick_routes (tenant_id, sort_order);

-- 2e. Crowd-sourced traffic samples.
--     There is NO free global live-traffic feed (Waze/HERE/TomTom are all
--     licensed). The only free real signal available to us is the speed our
--     own drivers, riders and buses report. We bucket those pings into ~150 m
--     cells and read the aggregate as the traffic condition of that cell.
CREATE TABLE IF NOT EXISTS public.traffic_samples (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  segment_key   TEXT NOT NULL,        -- rounded lat,lng cell
  lat           DOUBLE PRECISION NOT NULL,
  lng           DOUBLE PRECISION NOT NULL,
  speed_kmh     DOUBLE PRECISION NOT NULL,
  heading       DOUBLE PRECISION,
  source        TEXT NOT NULL DEFAULT 'driver'
                CHECK (source IN ('driver','rider','bus','user_report')),
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_traffic_samples_segment_time
  ON public.traffic_samples (segment_key, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_traffic_samples_time
  ON public.traffic_samples (recorded_at DESC);

ALTER TABLE public.traffic_samples ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY traffic_samples_read_authenticated ON public.traffic_samples
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Crowd-sourcing: any signed-in user contributes a speed reading.
DO $$ BEGIN
  CREATE POLICY traffic_samples_contribute ON public.traffic_samples
    FOR INSERT TO authenticated WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Segment condition for the area a user is looking at.
--   'unknown'  -> nobody has driven here recently (we say so, we do not invent)
--   'clear'    -> average speed >= 35 km/h
--   'moderate' -> 15..35 km/h
--   'heavy'    -> < 15 km/h, with at least 2 samples so one slow cyclist
--                 does not paint a whole city red
CREATE OR REPLACE FUNCTION public.get_traffic_segments(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_radius_deg DOUBLE PRECISION DEFAULT 0.02,
  p_minutes INT DEFAULT 30
) RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Group by the grid cell ONLY. Grouping by lat/lng as well would make every
  -- individual ping its own group (each one has a slightly different position),
  -- so every cell would report samples=1 and always read "unknown".
  WITH agg AS (
    SELECT ts.segment_key,
           avg(ts.lat)            AS lat,
           avg(ts.lng)            AS lng,
           count(*)               AS samples,
           avg(ts.speed_kmh)      AS avg_speed
      FROM public.traffic_samples ts
     WHERE ts.recorded_at > now() - make_interval(mins => p_minutes)
       AND ts.lat BETWEEN p_lat - p_radius_deg AND p_lat + p_radius_deg
       AND ts.lng BETWEEN p_lng - p_radius_deg AND p_lng + p_radius_deg
     GROUP BY ts.segment_key
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'lat',        a.lat,
    'lng',        a.lng,
    'avg_speed',  round(a.avg_speed::numeric, 1)::float8,
    'samples',    a.samples,
    'condition',  CASE
                    WHEN a.samples < 2 THEN 'unknown'
                    WHEN a.avg_speed < 15 THEN 'heavy'
                    WHEN a.avg_speed < 35 THEN 'moderate'
                    ELSE 'clear'
                  END,
    'source',     'crowd_sourced'
  )), '[]'::jsonb)
    FROM agg a;
$$;

REVOKE ALL ON FUNCTION public.get_traffic_segments(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_traffic_segments(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  TO authenticated, service_role;


-- Housekeeping: a bus pings every few seconds, so the table grows fast. Keep
-- only the recent history per bus.
CREATE OR REPLACE FUNCTION public.prune_bus_locations(
  p_bus_id UUID,
  p_keep INT DEFAULT 200
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.bus_locations
   WHERE bus_id = p_bus_id
     AND id NOT IN (
       SELECT id FROM public.bus_locations
        WHERE bus_id = p_bus_id
        ORDER BY recorded_at DESC
        LIMIT p_keep
     );
END;
$$;

REVOKE ALL ON FUNCTION public.prune_bus_locations(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prune_bus_locations(UUID, INT)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. STREAM AUDIENCE — who is watching, not just how many
-- ═══════════════════════════════════════════════════════════════════════════
-- stream_view_sessions already exists (20261121) with started/ended RPCs, but
-- nothing surfaced the audience to the streamer. The LATERAL pick-one-per-
-- user query is what makes "who has joined" correct: one user watching on two
-- devices is one person, not two.
CREATE OR REPLACE FUNCTION public.get_stream_audience(
  p_stream_id UUID,
  p_include_watchers BOOLEAN DEFAULT TRUE
) RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH live AS (
    SELECT DISTINCT ON (user_id) *
      FROM public.stream_view_sessions
     WHERE stream_id = p_stream_id
       AND left_at IS NULL
       AND last_seen_at > now() - interval '90 seconds'
     ORDER BY user_id, last_seen_at DESC
  ), watcher_list AS (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'user_id',   l.user_id,
      'name',      coalesce(p.full_name, 'Member'),
      'avatar_url',p.avatar_url,
      'role',      p.role,
      'joined_at', l.joined_at,
      'watched_seconds', coalesce(
        extract(epoch FROM (now() - l.joined_at))::int, 0)
    ) ORDER BY l.joined_at), '[]'::jsonb) AS watchers
      FROM live l
      LEFT JOIN public.profiles p ON p.id = l.user_id
  )
  SELECT jsonb_build_object(
    'viewers_now', (SELECT count(*) FROM live),
    'streamed_minutes', (
      SELECT round((extract(epoch FROM (now() - min(joined_at))) / 60)::numeric, 1)
        FROM public.stream_view_sessions
       WHERE stream_id = p_stream_id
    ),
    'watchers', CASE WHEN p_include_watchers
                     THEN (SELECT watchers FROM watcher_list)
                     ELSE '[]'::jsonb END
  );
$$;

REVOKE ALL ON FUNCTION public.get_stream_audience(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_stream_audience(UUID, BOOLEAN)
  TO authenticated, service_role;

-- Realtime so the studio count ticks up without a refresh.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname='supabase_realtime' AND schemaname='public'
       AND tablename='stream_view_sessions'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.stream_view_sessions';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname='supabase_realtime' AND schemaname='public'
       AND tablename='bus_locations'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.bus_locations';
  END IF;
END $$;
