-- 20261031 — Live-stream staleness: root cause of "live stream is not working".
-- A live_streams row is inserted with status='live' the moment a Cloudflare
-- input is created — BEFORE WHIP/OBS ever connects. If the operator abandons
-- it (app killed mid-start, WHIP failure, forgot END), the row stays 'live'
-- forever and UnifiedStreamService.checkStreamGate's concurrent check
-- (max_concurrent_streams = 1) then rejects EVERY future attempt with
-- "Maximum concurrent streams reached".
--
-- Fix: heartbeat + automatic expiry.
--   * Add last_heartbeat to live_streams (studio pings it every 30s while live).
--   * expire_stale_live_streams() marks abandoned live rows as ended:
--       - studio streams whose heartbeat stopped >4 min ago, OR
--       - any stream past the longest allowed duration (4h10m).
--     Rows with NULL heartbeat (OBS/RTMP encoders never run the app) are kept
--     alive until the duration cap — a legitimate OBS broadcast is never cut.
--   * Self-scoped: only the caller's own church unless superadmin/coa_employee.

ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS last_heartbeat timestamptz;

CREATE INDEX IF NOT EXISTS live_streams_status_heartbeat_idx
  ON public.live_streams (status, last_heartbeat);

CREATE OR REPLACE FUNCTION public.expire_stale_live_streams(p_church_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_own_tenant TEXT;
  v_staff BOOLEAN;
  v_expired INTEGER;
BEGIN
  -- Only the caller's own church (or platform staff) may expire rows.
  SELECT tenant_id::text INTO v_own_tenant
  FROM public.profiles WHERE id = auth.uid();
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee')
  ) INTO v_staff;

  IF NOT (v_staff OR v_own_tenant = p_church_id::text) THEN
    RETURN 0;
  END IF;

  UPDATE public.live_streams
  SET status = 'ended',
      ended_at = COALESCE(ended_at, now())
  WHERE church_id = p_church_id
    AND status = 'live'
    AND (
      (last_heartbeat IS NOT NULL AND last_heartbeat < now() - interval '4 minutes')
      OR
      (started_at IS NOT NULL AND started_at < now() - interval '4 hours 10 minutes')
    );

  GET DIAGNOSTICS v_expired = ROW_COUNT;
  RETURN v_expired;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.expire_stale_live_streams(uuid) FROM anon;