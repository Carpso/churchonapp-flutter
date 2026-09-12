-- 20261112: scheduled → live transition for church streams.
-- Scheduled streams previously sat in 'scheduled' forever: there was no code
-- path to promote them. This adds (a) a leadership-gated RPC for a manual
-- "Start Now" and (b) a pg_cron job that auto-starts streams once their
-- scheduled_at has passed (the Cloudflare live input is already provisioned at
-- schedule time, so flipping the status is enough to make it watchable).

-- (a) Manual "Start Now" — leadership only, same-tenant enforcement.
CREATE OR REPLACE FUNCTION public.start_scheduled_stream(p_stream_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church_id TEXT;
  v_ok BOOLEAN := false;
BEGIN
  SELECT church_id::text INTO v_church_id FROM public.live_streams WHERE id = p_stream_id;
  IF v_church_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND (
        p.role IN ('superadmin','coa_employee')
        OR (p.tenant_id::text = v_church_id AND p.role IN
            ('pastor','bishop','admin','apostle','prophet','general_secretary','leader','department_leader','general_treasurer'))
      )
  ) INTO v_ok;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Not authorized to start this stream';
  END IF;

  UPDATE public.live_streams
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         scheduled_at = NULL
   WHERE id = p_stream_id
     AND status = 'scheduled';

  RETURN FOUND;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.start_scheduled_stream(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_scheduled_stream(UUID) TO authenticated;

-- (b) Auto-start: promote any stream whose scheduled_at is in the past.
-- Runs via pg_cron (no auth.uid()) so it must be a plain helper.
CREATE OR REPLACE FUNCTION public.auto_start_due_streams()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.live_streams
     SET status = 'live',
         started_at = now(),
         scheduled_at = NULL
   WHERE status = 'scheduled'
     AND scheduled_at IS NOT NULL
     AND scheduled_at <= now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.auto_start_due_streams() FROM PUBLIC, anon;

-- (c) Cron: auto-start due streams every minute (idempotent reschedule).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-schedule-start') THEN
    PERFORM cron.unschedule('stream-schedule-start');
  END IF;
END $$;

SELECT cron.schedule('stream-schedule-start', '* * * * *', $$SELECT public.auto_start_due_streams()$$);

