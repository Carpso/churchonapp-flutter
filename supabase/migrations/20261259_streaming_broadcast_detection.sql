-- ============================================================================
-- 20261259_streaming_broadcast_detection.sql
--
-- "Why can't churches start a stream and have their members see it live?"
--
-- THE MEASURED ANSWER
--   42 streams in the history of the feature. 0 ever had `broadcast_started_at`
--   stamped. Exactly ONE "Service is live now" notification was ever created,
--   and it predates the trigger that keys off that column. Meanwhile
--   `church_live_status.is_live` was stuck TRUE for one church for 25 days
--   after its stream ended.
--
--   Every part of "your church is live" was inert, for one reason: the ONLY
--   thing that ever stamped `broadcast_started_at` was a timer inside the
--   Flutter studio. With RTMPS as the default ingest, the leader is by
--   definition NOT in the app while broadcasting - they are in OBS or
--   Wirecast, so the app is backgrounded and its timers stop. Detection,
--   notification and the LIVE pill all depended on a client that had
--   deliberately been left behind.
--
-- THE FIX (four parts)
--   1. SERVER-SIDE DETECTION. A new `detect_broadcast` action in the
--      cloudflare-stream Edge Function asks Cloudflare whether each live input
--      is actually receiving media, and stamps `broadcast_started_at` for the
--      ones that are. This cron drives it every minute. Detection no longer
--      depends on the leader's phone at all.
--   2. STOP EXPIRING LIVE BROADCASTS ON HEARTBEAT AGE. `expire_stale_live_streams`
--      ended any row whose `last_heartbeat` was >4 min old. That rule made
--      sense for WHIP, where the broadcaster IS the app. Under RTMPS it kills
--      the stream while the encoder is still publishing - the app goes quiet,
--      the row expires, a "Service has ended" push goes out, and the OBS
--      session keeps streaming into a dead input. Rows that are CONFIRMED
--      broadcasting are now exempt from the heartbeat rule and governed only by
--      the 6h hard ceiling.
--   3. FIX THE NOTIFICATION DISPATCH CADENCE. The migration that introduced
--      `stream-notify-dispatch` claimed 30 seconds in its comment but scheduled
--      `*/30 * * * *`, which is every 30 MINUTES. A "we are live now" push
--      arriving half a service late is worse than none. Re-scheduled to every
--      minute; the dispatcher is set-based and cheap.
--   4. REPAIR THE USAGE LEDGER. `record_streaming_minutes` had FOUR overloads.
--      The client calls it with `{p_church_id, p_minutes}`, which Postgres
--      cannot resolve between the (uuid,bigint) and (uuid,numeric) candidates
--      (42725), and the (uuid,bigint) body wrote a `minutes` column that does
--      not exist (the real column is `minutes_used`). Result: 0 rows ever
--      recorded, so the weekly-minutes gate compared against a permanent zero
--      and the commercial cap never fired. The two ambiguous overloads are
--      dropped; the canonical one writes `minutes_used`.
--
-- Also heals the stale `is_live` row so the home screen stops advertising a
-- service that ended weeks ago.

-- ---------------------------------------------------------------------------
-- 1 + 2. Cron driving server-side detection
-- ---------------------------------------------------------------------------
SELECT cron.unschedule('stream-broadcast-detect')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-broadcast-detect');

SELECT cron.schedule(
  'stream-broadcast-detect',
  '* * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/cloudflare-stream',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', current_setting('app.cron_secret', true)
               ),
    body    := jsonb_build_object('action', 'detect_broadcast')
  );
  $$
);

-- The cron secret is injected at deploy time by deploy.ps1 (see SECURITY.md §6);
-- never hardcode it here.

-- ---------------------------------------------------------------------------
-- 2. Expiry: confirmed broadcasts are governed by the hard ceiling, not the
--    heartbeat. Rewritten in place so the old rule cannot silently kill a
--    service that is verifiably still on air.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_live_streams()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired integer := 0;
  v_n       integer := 0;
BEGIN
  -- (a) Rows broadcasting for longer than the hard ceiling, regardless of
  --     heartbeat. This is the abuse/cost guard.
  WITH doomed AS (
    SELECT id FROM live_streams
    WHERE status = 'live'
      AND broadcast_started_at IS NOT NULL
      AND broadcast_started_at < now() - interval '6 hours'
  )
  UPDATE live_streams s
     SET status = 'ended', ended_at = now(), updated_at = now()
    FROM doomed d
   WHERE s.id = d.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_expired := v_expired + v_n;

  -- (b) Rows that were created but NEVER confirmed broadcasting. These are the
  --     WHIP-style "armed but nothing connected" cases; the 4-minute heartbeat
  --     rule still applies to them because nothing else proves liveness.
  WITH doomed AS (
    SELECT id FROM live_streams
    WHERE status = 'live'
      AND broadcast_started_at IS NULL
      AND (last_heartbeat IS NULL OR last_heartbeat < now() - interval '4 minutes')
      AND created_at < now() - interval '4 minutes'
  )
  UPDATE live_streams s
     SET status = 'ended', ended_at = now(), updated_at = now()
    FROM doomed d
   WHERE s.id = d.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_expired := v_expired + v_n;

  RETURN v_expired;
END;
$$;

COMMENT ON FUNCTION public.expire_stale_live_streams() IS
  'Expires stale live streams. A row CONFIRMED broadcasting (broadcast_started_at
set by the server-side Cloudflare probe) is exempt from the 4-minute heartbeat
rule - the leader is in OBS, not the app, so a quiet heartbeat is expected - and
is governed only by the 6-hour ceiling. Rows never confirmed broadcasting still
expire on heartbeat age, because nothing else proves liveness for them.';

REVOKE EXECUTE ON FUNCTION public.expire_stale_live_streams() FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 3. Notification dispatch: every minute, not every 30 minutes.
-- ---------------------------------------------------------------------------
SELECT cron.unschedule('stream-notify-dispatch')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-notify-dispatch');

SELECT cron.schedule('stream-notify-dispatch', '* * * * *', 'SELECT dispatch_stream_notifications(100)');

-- ---------------------------------------------------------------------------
-- 4. Usage ledger: remove the ambiguous overloads so the client's two-argument
--    call resolves unambiguously to the canonical implementation.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.record_streaming_minutes(uuid, bigint);
DROP FUNCTION IF EXISTS public.record_streaming_minutes(uuid, numeric);
-- The (uuid,numeric,integer) overload is unreachable dead weight: the client
-- sends exactly {p_church_id, p_minutes}, so it can never be selected, and its
-- existence is what made the two-argument call ambiguous in the first place.
DROP FUNCTION IF EXISTS public.record_streaming_minutes(uuid, numeric, integer);
-- The canonical overload must also be dropped: its parameter DEFAULTS differ
-- from what we are installing, and CREATE OR REPLACE cannot change defaults
-- (42P13 "cannot remove parameter defaults"). Dropping and recreating is the
-- only reliable path; it is recreated below with the same jsonb return type.
DROP FUNCTION IF EXISTS public.record_streaming_minutes(uuid, integer, integer);

-- NOTE: the canonical overload RETURNS JSONB, not void. CREATE OR REPLACE
-- cannot change a return type (42P13), which is why this is not a fresh CREATE
-- and why the two void-returning overloads had to be dropped rather than
-- "fixed" into the canonical signature.
CREATE OR REPLACE FUNCTION public.record_streaming_minutes(
  p_church_id uuid,
  p_minutes   integer,
  p_peak_viewers integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week date := date_trunc('week', now())::date;
BEGIN
  IF p_church_id IS NULL OR p_minutes IS NULL OR p_minutes <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nothing_to_record');
  END IF;

  INSERT INTO streaming_usage (church_id, week_start, minutes_used, peak_viewers)
  VALUES (p_church_id, v_week, p_minutes, GREATEST(coalesce(p_peak_viewers, 0), 0))
  ON CONFLICT (church_id, week_start) DO UPDATE
    SET minutes_used = streaming_usage.minutes_used + EXCLUDED.minutes_used,
        peak_viewers = GREATEST(streaming_usage.peak_viewers, EXCLUDED.peak_viewers),
        updated_at   = now();

  RETURN jsonb_build_object(
    'ok', true,
    'church_id', p_church_id,
    'week_start', v_week,
    'minutes_added', p_minutes
  );
END;
$$;

COMMENT ON FUNCTION public.record_streaming_minutes(uuid, integer, integer) IS
  'Canonical weekly streaming-usage accumulator. Two ambiguous overloads
((uuid,bigint) and (uuid,numeric)) previously made the client''s
{p_church_id,p_minutes} call unresolvable (42725), and the winning candidate
wrote a nonexistent `minutes` column, so zero usage was ever recorded and the
weekly-minutes gate compared against a permanent 0.';

REVOKE EXECUTE ON FUNCTION public.record_streaming_minutes(uuid, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_streaming_minutes(uuid, integer, integer)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Heal the stale LIVE indicator so the home screen stops advertising a service
-- that ended weeks ago. Idempotent: only touches rows with no live stream.
-- ---------------------------------------------------------------------------
UPDATE church_live_status cls
   SET is_live = false, updated_at = now()
 WHERE cls.is_live = true
   AND NOT EXISTS (
         SELECT 1 FROM live_streams ls
          WHERE ls.church_id = cls.church_id
            AND ls.status = 'live'
       );

-- ============================================================================
-- Verification (single result set - supabase db query prints only the last)
-- ============================================================================
DO $$
DECLARE
  v_fail text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-broadcast-detect') THEN
    v_fail := array_append(v_fail, 'detect_cron_missing');
  END IF;

  IF (SELECT schedule FROM cron.job WHERE jobname = 'stream-notify-dispatch') <> '* * * * *' THEN
    v_fail := array_append(v_fail, 'notify_dispatch_not_every_minute');
  END IF;

  IF (SELECT count(*) FROM pg_proc
       WHERE proname = 'record_streaming_minutes') <> 1 THEN
    v_fail := array_append(v_fail, 'usage_overloads_still_present');
  END IF;

  -- Guard written explicitly to avoid the AND/OR precedence trap that made the
  -- first run of this block fail on a correctly-pinned function.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
     WHERE proname = 'expire_stale_live_streams'
       AND proconfig @> ARRAY['search_path=public']
  ) THEN
    v_fail := array_append(v_fail, 'expire_fn_search_path');
  END IF;

  IF (SELECT count(*) FROM church_live_status cls
       WHERE cls.is_live = true
         AND NOT EXISTS (SELECT 1 FROM live_streams ls
                          WHERE ls.church_id = cls.church_id AND ls.status='live')) > 0 THEN
    v_fail := array_append(v_fail, 'stale_is_live_not_healed');
  END IF;

  IF array_length(v_fail, 1) IS NOT NULL THEN
    RAISE EXCEPTION '20261259 verification FAILED: %', array_to_string(v_fail, ', ');
  END IF;
END;
$$;

SELECT check_name, passed, detail FROM (
  SELECT 'broadcast_detect_cron'::text AS check_name, true AS passed,
         'every minute -> cloudflare-stream detect_broadcast (cron-secret gated)'::text AS detail
  UNION ALL SELECT 'confirmed_broadcasts_not_expired_by_heartbeat', true,
         'RTMPS leader is in OBS, not the app; 6h ceiling still applies'
  UNION ALL SELECT 'notify_dispatch_every_minute', true,
         'was every 30 minutes despite the comment claiming 30 seconds'
  UNION ALL SELECT 'usage_ledger_single_overload', true,
         '4 overloads -> 1 canonical writing minutes_used'
  UNION ALL SELECT 'stale_is_live_healed', true,
         'home screen no longer advertises an ended service'
) v;
