-- ============================================================================
-- 20261241_broadcast_started_signal.sql
--
-- Refines the "service started" notification introduced in 20261240.
--
-- THE BUG THIS FIXES
--   20261240 queued the "started" outbox row when `status` became 'live'.
--   But `createLiveStream()` inserts the row with status='live' the moment the
--   Cloudflare live input is created — BEFORE any encoder has published a
--   single frame. With the RTMPS/OBS path (the one that actually scales) a
--   leader can create the stream, get distracted, and never start OBS. The
--   congregation would still have been told "the service is live now".
--
-- THE FIX
--   Announce on a signal that means MEDIA IS ACTUALLY FLOWING, not on a row
--   that merely exists:
--     * WHIP  — the studio knows the WebRTC peer connected, so it stamps
--               `broadcast_started_at` immediately.
--     * RTMPS — the studio's 15 s heartbeat reads Cloudflare's live-input
--               status; the first time the input reports `connected`, the
--               studio stamps `broadcast_started_at`.
--   The "started" outbox row now fires on that column transitioning from NULL,
--   and `church_live_status` is flipped to is_live=true at the same moment.
--   `status='live'` still governs the "ended" transition and retention, so
--   nothing else changes.
--
-- This also makes the notification resilient to a leader who arms OBS, walks
-- away, and returns ten minutes later: no "service is live" push until frames
-- are actually arriving.
-- ============================================================================

ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS broadcast_started_at TIMESTAMPTZ;

COMMENT ON COLUMN public.live_streams.broadcast_started_at IS
  'Set the first time media was confirmed flowing (WHIP peer connected, or the Cloudflare live input reported connected). NULL = armed but not yet broadcasting.';

-- Keep the column honest if someone force-sets it on a non-live row.
CREATE OR REPLACE FUNCTION private.guard_broadcast_started()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.broadcast_started_at IS NOT NULL AND NEW.status <> 'live' THEN
    NEW.broadcast_started_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.guard_broadcast_started() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_live_streams_guard_broadcast_started ON public.live_streams;
CREATE TRIGGER trg_live_streams_guard_broadcast_started
  BEFORE INSERT OR UPDATE OF broadcast_started_at, status ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.guard_broadcast_started();

-- Replace the 20261240 queue trigger: "started" now keys off media flowing.
CREATE OR REPLACE FUNCTION private.queue_stream_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_kind TEXT;
BEGIN
  IF NEW.broadcast_started_at IS NOT NULL
     AND OLD.broadcast_started_at IS NULL THEN
    v_kind := 'started';
  ELSIF NEW.status IN ('ended', 'archived')
        AND COALESCE(OLD.status, '') NOT IN ('ended', 'archived') THEN
    v_kind := 'ended';
  ELSE
    RETURN NEW;
  END IF;

  IF NEW.church_id IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.stream_notification_outbox (stream_id, church_id, kind)
  VALUES (NEW.id, NEW.church_id, v_kind)
  ON CONFLICT (stream_id, kind) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN foreign_key_violation OR undefined_table THEN
  RETURN NEW; -- never let notification bookkeeping break the broadcast write
END;
$$;

DROP TRIGGER IF EXISTS trg_live_streams_queue_notification ON public.live_streams;
CREATE TRIGGER trg_live_streams_queue_notification
  AFTER INSERT OR UPDATE OF broadcast_started_at, status ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.queue_stream_notification();

-- Flip the member-visible "this church is live" flag at the same instant the
-- congregation is notified, so the home LIVE pill and the push can never
-- disagree about whether the service is actually running.
CREATE OR REPLACE FUNCTION private.sync_church_live_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.broadcast_started_at IS NULL AND OLD.broadcast_started_at IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.church_live_status AS c
    (church_id, is_live, title, stream_url, updated_at)
  VALUES (
    -- church_live_status.church_id must reference a real church row, and
    -- live_streams.church_id may hold the tenancy id (tenants.id and
    -- churches.id share the same uuid for all seeded data), so resolve the
    -- actual church before writing. If it cannot be resolved, skip rather than
    -- fail the broadcast.
    (SELECT c.id FROM public.churches c
      WHERE c.id = NEW.church_id OR c.tenant_id = NEW.church_id LIMIT 1),
    TRUE,
    COALESCE(NEW.title, 'Live Service'),
    COALESCE(NULLIF(NEW.hls_url, ''), NULLIF(NEW.preview_url, '')),
    now()
  )
  ON CONFLICT (church_id) DO UPDATE
    SET is_live    = TRUE,
        title      = COALESCE(EXCLUDED.title, c.title),
        stream_url = COALESCE(EXCLUDED.stream_url, c.stream_url),
        updated_at = now()
  WHERE c.church_id IS NOT NULL;

  RETURN NEW;
EXCEPTION WHEN undefined_table OR unique_violation OR not_null_violation THEN
  RETURN NEW; -- church_live_status shape drift must not break the broadcast
END;
$$;

REVOKE ALL ON FUNCTION private.sync_church_live_status() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_live_streams_sync_live_status ON public.live_streams;
CREATE TRIGGER trg_live_streams_sync_live_status
  AFTER UPDATE OF broadcast_started_at ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.sync_church_live_status();

-- Backfill: any row currently broadcasting should be announced once.
INSERT INTO public.stream_notification_outbox (stream_id, church_id, kind)
SELECT id, church_id, 'started'
  FROM public.live_streams
 WHERE status = 'live'
   AND church_id IS NOT NULL
   AND broadcast_started_at IS NULL
   AND COALESCE(started_at, created_at) > now() - interval '6 hours'
ON CONFLICT (stream_id, kind) DO NOTHING;

UPDATE public.live_streams
   SET broadcast_started_at = COALESCE(started_at, created_at)
 WHERE status = 'live'
   AND broadcast_started_at IS NULL
   AND COALESCE(started_at, created_at) > now() - interval '6 hours';
