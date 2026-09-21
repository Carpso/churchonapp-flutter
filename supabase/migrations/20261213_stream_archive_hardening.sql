-- ============================================================================
-- 20261213_stream_archive_hardening.sql
-- Bulletproofs the live-stream -> R2 archive safety net.
--
-- WHY: a finished service must ALWAYS end up archived even if the client never
-- called `endStream` (app closed mid-request) or the immediate archive hit the
-- Edge wall clock. The previous sweep (20261145) only looked at `ended` rows,
-- retried `failed` forever with no backoff, and never covered a stream stuck in
-- `live`. This adds attempt bookkeeping + backoff, a terminal failure after N
-- attempts (with the stored error), stale-`processing` recovery, and a
-- safety-net transition for `live` rows the client never ended.
-- ============================================================================

-- 1. Attempt bookkeeping (retry backoff + give-up cap).
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS archive_attempts        integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS archive_last_attempt_at timestamptz;

COMMENT ON COLUMN public.live_streams.archive_attempts IS
  'How many times the archive sweep has dispatched an R2 archive for this recording.';

-- Keep the "work to do" lookup cheap as the table grows.
CREATE INDEX IF NOT EXISTS idx_live_streams_archive_pending
  ON public.live_streams (archive_last_attempt_at)
  WHERE cloudflare_stream_id IS NOT NULL
    AND COALESCE(archive_status, 'none') <> 'ready';

-- 2. Rewritten sweep: (a) safety-net-ends stale live rows, (b) gives up after
--    N attempts, (c) dispatches eligible retries with exponential backoff.
CREATE OR REPLACE FUNCTION public.auto_archive_stream_recordings()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, private
AS $$
DECLARE
  v_row          record;
  v_n            int := 0;
  v_secret       text := private.get_cron_secret();
  v_max_attempts int  := 6;
BEGIN
  -- (a) Safety net: the client never called endStream (closed app, crashed
  --     phone). A `live` row older than a generous ceiling (6h > the 4h max
  --     configured stream duration) is treated as ended so it can be archived
  --     and materialised as a sermon. Setting status='ended' also fires the
  --     `trg_live_stream_recorded_service` sermon sync.
  UPDATE public.live_streams
     SET status    = 'ended',
         ended_at  = COALESCE(ended_at, now())
   WHERE status = 'live'
     AND COALESCE(started_at, created_at) < now() - interval '6 hours';

  IF v_secret IS NULL THEN
    RETURN 0;
  END IF;

  -- (b) Terminal failure after N attempts: store the error and STOP retrying
  --     forever. A leader can still trigger a manual archive from the UI.
  UPDATE public.live_streams
     SET archive_status = 'failed',
         archive_error  = COALESCE(
           NULLIF(btrim(archive_error), ''),
           'Archive failed after ' || v_max_attempts || ' attempts'
         )
   WHERE status IN ('ended', 'archived')
     AND cloudflare_stream_id IS NOT NULL
     AND COALESCE(archive_status, 'none') <> 'ready'
     AND archive_attempts >= v_max_attempts;

  -- (c) Dispatch eligible retries. Stale `processing`/`archiving` rows (an
  --     Edge invocation killed by the wall clock) are retried too.
  FOR v_row IN
    SELECT id, archive_attempts
      FROM public.live_streams
     WHERE status IN ('ended', 'archived')
       AND cloudflare_stream_id IS NOT NULL
       AND COALESCE(archive_status, 'none')
             IN ('none', 'queued', 'archiving', 'processing', 'failed')
       AND archive_attempts < v_max_attempts
       -- Give Cloudflare a few minutes to finalise the recording first.
       AND COALESCE(ended_at, created_at) < now() - interval '5 minutes'
       -- Exponential backoff: 5, 10, 20, 40, 80, 160, 320 minutes.
       AND (
         archive_last_attempt_at IS NULL
         OR archive_last_attempt_at < now()
              - (interval '5 minutes' * power(2, LEAST(archive_attempts, 6)))
       )
     ORDER BY COALESCE(archive_last_attempt_at, ended_at, created_at) ASC
     LIMIT 5
  LOOP
    UPDATE public.live_streams
       SET archive_attempts        = v_row.archive_attempts + 1,
           archive_last_attempt_at = now(),
           archive_status          = CASE
             WHEN COALESCE(archive_status, 'none') = 'none' THEN 'queued'
             ELSE archive_status
           END
     WHERE id = v_row.id;

    PERFORM net.http_post(
      url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/cloudflare-stream',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', v_secret
      ),
      body := jsonb_build_object('action', 'archive_recording', 'stream_id', v_row.id)
    );
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
EXCEPTION WHEN undefined_function OR undefined_table THEN
  RETURN 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_archive_stream_recordings() FROM anon;
REVOKE EXECUTE ON FUNCTION public.auto_archive_stream_recordings() FROM authenticated;

-- 3. Reschedule the sweep (10 min) — idempotent.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-archive-sweep') THEN
      PERFORM cron.unschedule('stream-archive-sweep');
    END IF;
    PERFORM cron.schedule(
      'stream-archive-sweep',
      '*/10 * * * *',
      $cron$SELECT public.auto_archive_stream_recordings();$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
