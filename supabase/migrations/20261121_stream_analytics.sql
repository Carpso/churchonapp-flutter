-- Streaming analytics: per-viewer sessions, daily rollups, and two access
-- surfaces (COA platform-wide + tenant-scoped) with Cloudflare Stream cost
-- attribution.
--
-- Gaps this closes:
--   * per-service peak / unique viewers over time
--   * watch-time + retention curves
--   * per-tenant CF stream-minute cost attribution
--   * a tenant-facing dashboard (plus a COA platform-wide roll-up)

-- ---------------------------------------------------------------------------
-- 1) Raw per-viewer sessions (written by the app while watching)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stream_view_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id       uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  tenant_id       uuid,
  user_id         uuid NOT NULL,
  joined_at       timestamptz NOT NULL DEFAULT now(),
  left_at         timestamptz,
  watched_seconds integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_svs_stream  ON public.stream_view_sessions(stream_id);
CREATE INDEX IF NOT EXISTS idx_svs_tenant  ON public.stream_view_sessions(tenant_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_svs_user    ON public.stream_view_sessions(user_id, joined_at DESC);

ALTER TABLE public.stream_view_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Viewers insert own stream sessions" ON public.stream_view_sessions;
CREATE POLICY "Viewers insert own stream sessions" ON public.stream_view_sessions
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Viewers read own stream sessions" ON public.stream_view_sessions;
CREATE POLICY "Viewers read own stream sessions" ON public.stream_view_sessions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Leadership read tenant stream sessions" ON public.stream_view_sessions;
CREATE POLICY "Leadership read tenant stream sessions" ON public.stream_view_sessions
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin', 'coa_employee')
          OR (p.tenant_id IS NOT NULL AND p.tenant_id::text = stream_view_sessions.tenant_id::text
              AND p.role IN ('pastor','bishop','apostle','prophet','admin','leader',
                             'general_secretary','general_treasurer','treasurer','department_leader'))
        )
    )
  );

GRANT SELECT, INSERT ON public.stream_view_sessions TO authenticated;
REVOKE ALL ON public.stream_view_sessions FROM anon;

-- ---------------------------------------------------------------------------
-- 2) Daily rollup
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stream_analytics_daily (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day                   date NOT NULL,
  stream_id             uuid NOT NULL,
  tenant_id             uuid,
  title                 text,
  peak_viewers          integer NOT NULL DEFAULT 0,
  unique_viewers        integer NOT NULL DEFAULT 0,
  sessions              integer NOT NULL DEFAULT 0,
  watch_minutes         numeric NOT NULL DEFAULT 0,
  avg_watch_minutes     numeric NOT NULL DEFAULT 0,
  broadcast_minutes     integer NOT NULL DEFAULT 0,
  delivered_minutes     numeric NOT NULL DEFAULT 0, -- ≈ CF delivery bill
  retention             jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivery_cost_kwacha  numeric NOT NULL DEFAULT 0,
  storage_cost_kwacha   numeric NOT NULL DEFAULT 0,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_sad_stream_day ON public.stream_analytics_daily(stream_id, day);
CREATE INDEX IF NOT EXISTS idx_sad_tenant_day ON public.stream_analytics_daily(tenant_id, day DESC);

ALTER TABLE public.stream_analytics_daily ENABLE ROW LEVEL SECURITY;

-- Read-only for leadership + COA; writes happen only via the SECURITY DEFINER
-- rollup function (service role / cron).
DROP POLICY IF EXISTS "Leadership read stream analytics" ON public.stream_analytics_daily;
CREATE POLICY "Leadership read stream analytics" ON public.stream_analytics_daily
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin', 'coa_employee')
          OR (p.tenant_id IS NOT NULL AND p.tenant_id::text = stream_analytics_daily.tenant_id::text
              AND p.role IN ('pastor','bishop','apostle','prophet','admin','leader',
                             'general_secretary','general_treasurer','treasurer','department_leader'))
        )
    )
  );

GRANT SELECT ON public.stream_analytics_daily TO authenticated;
REVOKE ALL ON public.stream_analytics_daily FROM anon;

-- ---------------------------------------------------------------------------
-- 3) Session lifecycle RPCs (called by the viewer)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stream_start_session(p_stream_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant    uuid;
  v_session   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT church_id INTO v_tenant FROM live_streams WHERE id = p_stream_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stream not found';
  END IF;

  INSERT INTO stream_view_sessions (stream_id, tenant_id, user_id)
  VALUES (p_stream_id, v_tenant, v_uid)
  RETURNING id INTO v_session;

  RETURN v_session;
END;
$$;

CREATE OR REPLACE FUNCTION public.stream_end_session(p_session_id uuid, p_watched_seconds integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE stream_view_sessions
     SET left_at = now(),
         watched_seconds = GREATEST(COALESCE(p_watched_seconds, 0), 0)
   WHERE id = p_session_id
     AND user_id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.stream_start_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.stream_end_session(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.stream_start_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stream_end_session(uuid, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Cost rates (remote-configurable)
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value) VALUES
  ('cf_stream_delivery_usd_per_1000_min', '1.0'),
  ('cf_stream_storage_usd_per_1000_min', '5.0'),
  ('cf_stream_usd_to_zmw', '18.0')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5) Rollup RPC (service role / cron only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rollup_stream_analytics(p_day date DEFAULT ((now() - interval '1 day')::date))
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_rate numeric := COALESCE((SELECT value::numeric FROM platform_settings WHERE key = 'cf_stream_delivery_usd_per_1000_min'), 1.0);
  v_storage_rate  numeric := COALESCE((SELECT value::numeric FROM platform_settings WHERE key = 'cf_stream_storage_usd_per_1000_min'), 5.0);
  v_fx            numeric := COALESCE((SELECT value::numeric FROM platform_settings WHERE key = 'cf_stream_usd_to_zmw'), 18.0);
  v_count         integer := 0;
BEGIN
  -- Aggregate sessions that started on the given day, per stream.
  WITH agg AS (
    SELECT
      s.stream_id,
      s.tenant_id,
      count(*)                                AS sessions,
      count(DISTINCT s.user_id)               AS unique_viewers,
      COALESCE(sum(s.watched_seconds), 0) / 60.0 AS watch_minutes,
      -- Rough retention curve: share of sessions still watching past N minutes.
      jsonb_build_object(
        '1',  ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 60))::numeric   / GREATEST(count(*),1), 3),
        '5',  ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 300))::numeric  / GREATEST(count(*),1), 3),
        '10', ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 600))::numeric  / GREATEST(count(*),1), 3),
        '20', ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 1200))::numeric / GREATEST(count(*),1), 3),
        '30', ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 1800))::numeric / GREATEST(count(*),1), 3),
        '60', ROUND( (count(*) FILTER (WHERE s.watched_seconds >= 3600))::numeric / GREATEST(count(*),1), 3)
      ) AS retention
    FROM stream_view_sessions s
    WHERE s.joined_at >= p_day::timestamptz
      AND s.joined_at <  (p_day + 1)::timestamptz
    GROUP BY s.stream_id, s.tenant_id
  ),
  joined AS (
    SELECT
      a.*,
      ls.title,
      ls.viewer_count,
      GREATEST(
        COALESCE(EXTRACT(EPOCH FROM (COALESCE(ls.ended_at, ls.started_at, ls.created_at) - COALESCE(ls.started_at, ls.created_at))) / 60, 0),
        0
      )::int AS broadcast_minutes
    FROM agg a
    JOIN live_streams ls ON ls.id = a.stream_id
  )
  INSERT INTO stream_analytics_daily AS d (
    day, stream_id, tenant_id, title, peak_viewers, unique_viewers, sessions,
    watch_minutes, avg_watch_minutes, broadcast_minutes, delivered_minutes,
    retention, delivery_cost_kwacha, storage_cost_kwacha, updated_at
  )
  SELECT
    p_day,
    j.stream_id,
    j.tenant_id,
    j.title,
    GREATEST(COALESCE(j.viewer_count, 0), j.unique_viewers) AS peak_viewers,
    j.unique_viewers,
    j.sessions,
    ROUND(j.watch_minutes, 2),
    ROUND(j.watch_minutes / GREATEST(j.unique_viewers, 1), 2),
    j.broadcast_minutes,
    ROUND(j.watch_minutes, 2),
    j.retention,
    ROUND((j.watch_minutes / 1000.0) * v_delivery_rate * v_fx, 2),
    ROUND((j.broadcast_minutes / 1000.0) * v_storage_rate * v_fx, 2),
    now()
  FROM joined j
  ON CONFLICT (stream_id, day) DO UPDATE SET
    title = EXCLUDED.title,
    peak_viewers = GREATEST(d.peak_viewers, EXCLUDED.peak_viewers),
    unique_viewers = EXCLUDED.unique_viewers,
    sessions = EXCLUDED.sessions,
    watch_minutes = EXCLUDED.watch_minutes,
    avg_watch_minutes = EXCLUDED.avg_watch_minutes,
    broadcast_minutes = EXCLUDED.broadcast_minutes,
    delivered_minutes = EXCLUDED.delivered_minutes,
    retention = EXCLUDED.retention,
    delivery_cost_kwacha = EXCLUDED.delivery_cost_kwacha,
    storage_cost_kwacha = EXCLUDED.storage_cost_kwacha,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rollup_stream_analytics(date) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6) Tenant-facing analytics (leadership of that tenant, or COA)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_tenant_stream_analytics(
  p_tenant_id uuid,
  p_from date DEFAULT ((now() - interval '30 day')::date),
  p_to   date DEFAULT (now()::date)
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ok  boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = v_uid
      AND (
        p.role IN ('superadmin','coa_employee')
        OR (p.tenant_id IS NOT NULL AND p.tenant_id::text = p_tenant_id::text
            AND p.role IN ('pastor','bishop','apostle','prophet','admin','leader',
                           'general_secretary','general_treasurer','treasurer','department_leader'))
      )
  ) INTO v_ok;
  IF NOT v_ok THEN RAISE EXCEPTION 'Not authorized for this church'; END IF;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'from', p_from,
    'to', p_to,
    'totals', (
      SELECT jsonb_build_object(
        'services', count(DISTINCT stream_id),
        'peak_viewers', COALESCE(max(peak_viewers), 0),
        'unique_viewers', COALESCE(sum(unique_viewers), 0),
        'watch_minutes', ROUND(COALESCE(sum(watch_minutes), 0), 2),
        'avg_watch_minutes', ROUND(COALESCE(avg(avg_watch_minutes), 0), 2),
        'broadcast_minutes', COALESCE(sum(broadcast_minutes), 0),
        'delivered_minutes', ROUND(COALESCE(sum(delivered_minutes), 0), 2),
        'delivery_cost_kwacha', ROUND(COALESCE(sum(delivery_cost_kwacha), 0), 2),
        'storage_cost_kwacha', ROUND(COALESCE(sum(storage_cost_kwacha), 0), 2)
      ) FROM stream_analytics_daily
      WHERE tenant_id::text = p_tenant_id::text AND day BETWEEN p_from AND p_to
    ),
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'day', day,
        'peak_viewers', peak_viewers,
        'unique_viewers', unique_viewers,
        'watch_minutes', watch_minutes,
        'delivered_minutes', delivered_minutes,
        'delivery_cost_kwacha', delivery_cost_kwacha
      ) ORDER BY day)
      FROM stream_analytics_daily
      WHERE tenant_id::text = p_tenant_id::text AND day BETWEEN p_from AND p_to
    ), '[]'::jsonb),
    'services', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.day DESC)
      FROM (
        SELECT day, stream_id, title, peak_viewers, unique_viewers, sessions,
               watch_minutes, avg_watch_minutes, broadcast_minutes, retention,
               delivery_cost_kwacha
        FROM stream_analytics_daily
        WHERE tenant_id::text = p_tenant_id::text AND day BETWEEN p_from AND p_to
        ORDER BY day DESC
        LIMIT 50
      ) t
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_tenant_stream_analytics(uuid, date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_tenant_stream_analytics(uuid, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7) COA platform-wide analytics (superadmin / coa_employee only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_stream_analytics(
  p_from date DEFAULT ((now() - interval '30 day')::date),
  p_to   date DEFAULT (now()::date)
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ok  boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = v_uid AND p.role IN ('superadmin','coa_employee')
  ) INTO v_ok;
  IF NOT v_ok THEN RAISE EXCEPTION 'COA staff only'; END IF;

  RETURN jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'totals', (
      SELECT jsonb_build_object(
        'churches', count(DISTINCT tenant_id),
        'services', count(DISTINCT stream_id),
        'peak_viewers', COALESCE(max(peak_viewers), 0),
        'unique_viewers', COALESCE(sum(unique_viewers), 0),
        'watch_minutes', ROUND(COALESCE(sum(watch_minutes), 0), 2),
        'broadcast_minutes', COALESCE(sum(broadcast_minutes), 0),
        'delivered_minutes', ROUND(COALESCE(sum(delivered_minutes), 0), 2),
        'delivery_cost_kwacha', ROUND(COALESCE(sum(delivery_cost_kwacha), 0), 2),
        'storage_cost_kwacha', ROUND(COALESCE(sum(storage_cost_kwacha), 0), 2),
        'total_cost_kwacha', ROUND(COALESCE(sum(delivery_cost_kwacha) + sum(storage_cost_kwacha), 0), 2)
      ) FROM stream_analytics_daily WHERE day BETWEEN p_from AND p_to
    ),
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'day', day, 'watch_minutes', watch_minutes, 'peak_viewers', peak_viewers,
        'unique_viewers', unique_viewers, 'delivered_minutes', delivered_minutes,
        'delivery_cost_kwacha', delivery_cost_kwacha, 'storage_cost_kwacha', storage_cost_kwacha
      ) ORDER BY day)
      FROM (
        SELECT day,
               ROUND(sum(watch_minutes), 2) watch_minutes,
               COALESCE(max(peak_viewers), 0) peak_viewers,
               COALESCE(sum(unique_viewers), 0) unique_viewers,
               ROUND(sum(delivered_minutes), 2) delivered_minutes,
               ROUND(sum(delivery_cost_kwacha), 2) delivery_cost_kwacha,
               ROUND(sum(storage_cost_kwacha), 2) storage_cost_kwacha
        FROM stream_analytics_daily WHERE day BETWEEN p_from AND p_to
        GROUP BY day
      ) d
    ), '[]'::jsonb),
    'by_church', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.delivery_cost_kwacha DESC)
      FROM (
        SELECT tenant_id,
               count(DISTINCT stream_id) services,
               COALESCE(sum(unique_viewers), 0) unique_viewers,
               ROUND(sum(watch_minutes), 2) watch_minutes,
               ROUND(sum(delivered_minutes), 2) delivered_minutes,
               ROUND(sum(delivery_cost_kwacha), 2) delivery_cost_kwacha,
               ROUND(sum(storage_cost_kwacha), 2) storage_cost_kwacha
        FROM stream_analytics_daily WHERE day BETWEEN p_from AND p_to
        GROUP BY tenant_id
      ) t
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_platform_stream_analytics(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_platform_stream_analytics(date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) Nightly rollup (pg_cron) — safe no-op if pg_cron isn't available
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('stream-analytics-rollup')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-analytics-rollup');
    PERFORM cron.schedule(
      'stream-analytics-rollup',
      '20 1 * * *',
      $cron$SELECT public.rollup_stream_analytics((now() - interval '1 day')::date);$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
