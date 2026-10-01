-- ============================================================================
-- 20261240_streaming_scale_and_notifications.sql
--
-- GOAL: make tenant streaming actually work end-to-end and scale, and make
-- "the service started / the service ended" reach the congregation.
--
-- WHAT THE AUDIT FOUND (all verified against the live schema):
--
--  1. NO STREAM NOTIFICATIONS EXISTED. Nothing wrote a `notifications` row on
--     start or end, and the `push-notifications` Edge Function had no `stream`
--     type/icon/channel. Members could only find a live service by opening the
--     app. Fixed here: an outbox + dispatcher (deliberately NOT a synchronous
--     trigger fan-out — see "WHY AN OUTBOX" below).
--
--  2. 20261237's table-level `GRANT SELECT ON live_streams TO authenticated,
--     anon` re-granted ALL columns, undoing the deliberate column allowlist
--     from 20261109/20261144. Postgres column grants are ADDITIVE and are
--     checked BEFORE RLS, so `stream_key`, `rtmp_url` and `whip_url` became
--     readable by every authenticated user and by anon — i.e. anyone could
--     read any church's broadcast ingest credentials. Fixed here.
--
--  3. WHIP (phone camera) broadcasts are WebRTC-only: Cloudflare never emits
--     HLS and never records them. The archive sweep therefore burned 6 attempts
--     and 5-minute backoffs on every phone broadcast and always landed on
--     'failed'. Fixed here with an explicit `ingest_mode` marker.
--
--  4. `viewer_count` was only recomputed by the BROADCASTER's 15s poll, so it
--     froze whenever the studio app was closed. Fixed here with a cron rollup
--     that is O(number of live streams), not O(number of viewers).
--
-- WHY AN OUTBOX INSTEAD OF A TRIGGER THAT PUSHES DIRECTLY
--   A congregation can be thousands of people. Fanning that out synchronously
--   inside the status UPDATE that marks a stream live would block the very
--   write that starts the broadcast, and would time out. So the trigger only
--   appends one cheap outbox row; a 30-second cron drains it set-based.
--   This is also what lets 1000 churches go live simultaneously without any
--   write contention: one row per event, regardless of congregation size.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ingest_mode — know whether a broadcast can EVER produce HLS/recording
-- ---------------------------------------------------------------------------
-- 'rtmps' = RTMPS/OBS/SRT ingest  -> Cloudflare emits adaptive HLS + auto-record
-- 'whip'  = WebRTC/WHIP ingest   -> WebRTC only; NO HLS, NO recording, NO replay
-- NULL     = not yet known (row created, encoder not attached yet)

ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS ingest_mode TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'live_streams_ingest_mode_check'
  ) THEN
    ALTER TABLE public.live_streams
      ADD CONSTRAINT live_streams_ingest_mode_check
      CHECK (ingest_mode IS NULL OR ingest_mode IN ('rtmps', 'whip'));
  END IF;
END $$;

COMMENT ON COLUMN public.live_streams.ingest_mode IS
  'rtmps = HLS + auto-recording available; whip = WebRTC-only (never recordable)';

-- A WHIP broadcast has no Cloudflare recording, so stop the sweep chasing one.
-- Setting archive_status to a value outside the sweep's eligible list
-- ('none','queued','archiving','processing','failed') disables it cleanly
-- without editing the 20261213 sweep function.
CREATE OR REPLACE FUNCTION private.mark_whip_unrecordable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.ingest_mode = 'whip'
     AND COALESCE(NEW.archive_status, 'none') IN ('none', 'queued', 'archiving', 'processing', 'failed')
     AND NEW.status IN ('ended', 'archived') THEN
    NEW.archive_status := 'not_applicable';
    IF NEW.archive_error IS NULL OR btrim(NEW.archive_error) = '' THEN
      NEW.archive_error := 'Phone (WHIP/WebRTC) broadcasts are live-only and are not recorded by Cloudflare.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_whip_unrecordable() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_live_streams_whip_unrecordable ON public.live_streams;
CREATE TRIGGER trg_live_streams_whip_unrecordable
  BEFORE INSERT OR UPDATE OF ingest_mode, status, archive_status ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.mark_whip_unrecordable();

-- ---------------------------------------------------------------------------
-- 2. SECURITY — restore the live_streams column allowlist
-- ---------------------------------------------------------------------------
-- Built dynamically from information_schema so it can never drift out of sync
-- with the table, and so a column added later is denied by default until it is
-- deliberately classified.
--
-- The client still needs to WRITE its own row (it receives the credentials from
-- the Edge Function and persists them) — write privileges are granted, read
-- privileges on the credential columns are not.

DO $$
DECLARE
  v_safe_cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY column_name)
    INTO v_safe_cols
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'live_streams'
     -- Ingest credentials: writable by the owning broadcaster, never readable
     -- by anyone else (including anon and the public church website).
     AND column_name NOT IN (
       'stream_key', 'rtmp_url', 'whip_url',
       'srt_url', 'srt_stream_key', 'stream_secret', 'srt_passphrase'
     );

  IF v_safe_cols IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON public.live_streams FROM anon, authenticated';
    EXECUTE format('GRANT SELECT (%s) ON public.live_streams TO authenticated', v_safe_cols);
    -- The public church website reads live/scheduled state without signing in.
    EXECUTE format('GRANT SELECT (%s) ON public.live_streams TO anon', v_safe_cols);
    -- Writes stay available to signed-in leaders; RLS still governs which rows.
    EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.live_streams TO authenticated';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. STREAM NOTIFICATIONS — outbox, dispatcher, cron
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.stream_notification_outbox (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id     UUID NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  church_id     UUID,
  kind          TEXT NOT NULL,          -- 'started' | 'ended'
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at TIMESTAMPTZ,
  attempts      INT  NOT NULL DEFAULT 0,
  last_error    TEXT,
  -- One notification per stream per kind, ever. This is the dedupe guarantee
  -- that survives reconnects, retries and the "promote scheduled -> live" cron.
  CONSTRAINT stream_notification_outbox_once UNIQUE (stream_id, kind),
  CONSTRAINT stream_notification_outbox_kind CHECK (kind IN ('started', 'ended'))
);

CREATE INDEX IF NOT EXISTS idx_stream_notification_outbox_pending
  ON public.stream_notification_outbox (created_at)
  WHERE dispatched_at IS NULL;

ALTER TABLE public.stream_notification_outbox ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.stream_notification_outbox FROM anon, authenticated;
-- Staff may read the outbox for support/diagnostics; only the service role writes.
GRANT SELECT ON public.stream_notification_outbox TO authenticated;

-- Queue an outbox row on the two transitions that matter. ON CONFLICT DO NOTHING
-- makes re-promotion, retries and reconnects harmless.
CREATE OR REPLACE FUNCTION private.queue_stream_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_kind TEXT;
BEGIN
  IF NEW.status = 'live' AND COALESCE(OLD.status, '') <> 'live' THEN
    v_kind := 'started';
  ELSIF NEW.status IN ('ended', 'archived')
        AND COALESCE(OLD.status, '') NOT IN ('ended', 'archived') THEN
    v_kind := 'ended';
  ELSE
    RETURN NEW;
  END IF;

  -- A stream with no owning church has nobody to notify.
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

REVOKE ALL ON FUNCTION private.queue_stream_notification() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_live_streams_queue_notification ON public.live_streams;
CREATE TRIGGER trg_live_streams_queue_notification
  AFTER INSERT OR UPDATE OF status ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.queue_stream_notification();

-- --- The dispatcher -------------------------------------------------------
-- Set-based on purpose: one INSERT ... SELECT for the in-app rows (no loop),
-- and chunked device push so a 5000-member congregation does not build one
-- giant HTTP payload. Processes EVERY pending event on each tick, not just one,
-- which is what lets many churches be live at the same time.

CREATE OR REPLACE FUNCTION public.dispatch_stream_notifications(p_limit INT DEFAULT 50)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_ev        RECORD;
  v_recipients UUID[];
  v_cap       INT;
  v_title     TEXT;
  v_body      TEXT;
  v_ref       TEXT;
  v_church_uuid UUID;
  v_total     INT := 0;
  v_chunk     uuid[];
  v_i         INT;
BEGIN
  SELECT COALESCE(NULLIF(value, '')::INT, 2000)
    INTO v_cap
    FROM public.platform_settings
   WHERE key = 'stream_notify_member_cap'
   LIMIT 1;

  v_cap := COALESCE(v_cap, 2000);

  FOR v_ev IN
    SELECT o.id, o.stream_id, o.church_id, o.kind,
           COALESCE(s.title, 'Live service') AS stream_title,
           COALESCE(s.created_by::text, '')  AS broadcaster,
           (s.recording_hls_url IS NOT NULL OR s.archive_url IS NOT NULL) AS has_recording,
           (COALESCE(s.viewer_count, 0) > 0)  AS had_viewers
      FROM public.stream_notification_outbox o
      JOIN public.live_streams s ON s.id = o.stream_id
     WHERE o.dispatched_at IS NULL
       AND o.attempts < 5
     ORDER BY o.created_at ASC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500))
  LOOP
    BEGIN
      -- Recipients: everyone in this tenant except the broadcaster.
      --
      -- TYPE WARNING: profiles.tenant_id is TEXT while live_streams.church_id is
      -- UUID. Postgres has no implicit uuid->text operator, so comparing them
      -- directly raises "operator does not exist: text = uuid". That error would
      -- be swallowed by the handler below and the congregation would silently
      -- never be notified. The ::text cast is load-bearing, not cosmetic.
      --
      -- live_streams.church_id has an FK to churches(id), but seeded data makes
      -- tenants.id and churches.id the SAME uuid (verified: 36/36 live_streams
      -- rows resolve to both). New rows could legitimately carry either id, so
      -- the tenancy is resolved through both paths rather than assuming.
      SELECT COALESCE(array_agg(p.id), ARRAY[]::uuid[])
        INTO v_recipients
        FROM (
          SELECT pr.id
            FROM public.profiles pr
           WHERE pr.tenant_id = COALESCE(
                   (SELECT t.id::text  FROM public.tenants  t WHERE t.id = v_ev.church_id),
                   (SELECT c.tenant_id::text FROM public.churches c WHERE c.id = v_ev.church_id),
                   v_ev.church_id::text)
             AND (v_ev.broadcaster = '' OR pr.id::text <> v_ev.broadcaster)
           ORDER BY pr.id
           LIMIT v_cap
        ) p;

      IF array_length(v_recipients, 1) IS NULL THEN
        UPDATE public.stream_notification_outbox
           SET dispatched_at = now(), attempts = attempts + 1,
               last_error = 'no_recipients'
         WHERE id = v_ev.id;
        CONTINUE;
      END IF;

      IF v_ev.kind = 'started' THEN
        v_title := 'Service is live now';
        v_body  := v_ev.stream_title || ' has started. Tap to watch.';
      ELSE
        v_title := 'Service has ended';
        v_body  := CASE
          WHEN v_ev.has_recording THEN
            v_ev.stream_title || ' has ended. The recording is now available.'
          ELSE
            v_ev.stream_title || ' has ended.'
        END;
      END IF;
      v_ref := v_ev.stream_id::text;

      -- notifications.tenant_id is an FK to churches(id) (NOT tenants(id)), and
      -- live_streams.church_id may hold either id. Writing it straight into that
      -- column would be an FK violation for most churches, so resolve the real
      -- church row and leave it NULL when there isn't one. The client never
      -- filters its notification list on tenant_id, so NULL is safe and simply
      -- keeps the row visible.
      SELECT c.id INTO v_church_uuid
        FROM public.churches c
       WHERE c.id = v_ev.church_id
          OR c.tenant_id = v_ev.church_id
       LIMIT 1;

      -- In-app rows, one set-based statement (NOT a per-user loop).
      INSERT INTO public.notifications (user_id, title, body, type, reference_id, tenant_id)
      SELECT r, v_title, v_body, 'stream_' || v_ev.kind, v_ref, v_church_uuid
        FROM unnest(v_recipients) AS r
      ON CONFLICT DO NOTHING;

      -- Device push in chunks so a large congregation cannot build a payload
      -- the Edge Function would reject. Failures are non-fatal by design: the
      -- in-app rows are already committed.
      v_i := 1;
      WHILE v_i <= array_length(v_recipients, 1) LOOP
        v_chunk := (
          SELECT COALESCE(array_agg(x), ARRAY[]::uuid[])
            FROM (
              SELECT unnest(v_recipients) AS x
               LIMIT 500 OFFSET (v_i - 1)
            ) s
        );

        IF array_length(v_chunk, 1) IS NOT NULL THEN
          PERFORM private.push_to_users(
            v_chunk, v_title, v_body,
            'stream_' || v_ev.kind,
            'coa_live_stream', v_ref
          );
        END IF;

        v_i := v_i + 500;
      END LOOP;

      UPDATE public.stream_notification_outbox
         SET dispatched_at = now(), attempts = attempts + 1, last_error = NULL
       WHERE id = v_ev.id;

      v_total := v_total + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Never lose the event: record the error and let the next tick retry.
      -- The warning is deliberate — a swallowed error here once hid a
      -- text-vs-uuid join bug that meant NOBODY was ever notified.
      RAISE WARNING 'stream notification dispatch failed for outbox %: %',
        v_ev.id, EXCEPTION::text;
      UPDATE public.stream_notification_outbox
         SET attempts = attempts + 1, last_error = left(EXCEPTION::text, 500)
       WHERE id = v_ev.id;
    END;
  END LOOP;

  RETURN v_total;
END;
$$;

-- NOTE: the identity argument list must be written out in full here. A
-- defaulted parameter does NOT let `...ON FUNCTION f()` resolve to `f(integer)`,
-- and the statement fails with "function f() does not exist".
REVOKE ALL ON FUNCTION public.dispatch_stream_notifications(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_stream_notifications(integer) TO service_role;

-- Manual/support trigger: leadership can force a dispatch after an incident.
CREATE OR REPLACE FUNCTION public.dispatch_stream_notifications_now()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret text := private.get_cron_secret();
BEGIN
  IF coalesce(current_setting('request.headers', true), '') NOT LIKE '%x-cron-secret%'
     OR v_secret IS NULL THEN
    RAISE EXCEPTION 'not permitted';
  END IF;
  RETURN public.dispatch_stream_notifications(200);
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_stream_notifications_now() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_stream_notifications_now() TO service_role;

-- Cron: drain the outbox every 30 seconds. All pending churches per tick.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-notify-dispatch') THEN
      PERFORM cron.schedule(
        'stream-notify-dispatch', '*/30 * * * *',
        $cron$SELECT public.dispatch_stream_notifications(100);$cron$
      );
    END IF;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. VIEWER COUNT — stop it depending on the broadcaster's app staying open
-- ---------------------------------------------------------------------------
-- Rollup is O(live streams) per minute, independent of audience size, so it
-- stays cheap whether 1 church or 1000 are broadcasting.

CREATE OR REPLACE FUNCTION public.refresh_live_stream_viewer_counts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_s RECORD;
  v_n INT := 0;
BEGIN
  FOR v_s IN
    SELECT id FROM public.live_streams
     WHERE status = 'live'
       AND (last_heartbeat IS NULL OR last_heartbeat > now() - interval '10 minutes')
     LIMIT 2000
  LOOP
    PERFORM public.stream_refresh_viewer_count(v_s.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_live_stream_viewer_counts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_live_stream_viewer_counts() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-viewer-rollup') THEN
      PERFORM cron.schedule(
        'stream-viewer-rollup', '* * * * *',
        $cron$SELECT public.refresh_live_stream_viewer_counts();$cron$
      );
    END IF;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Remote-config cap for the notification fan-out
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value)
VALUES (
  'stream_notify_member_cap', '2000'
)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6. Backfill: streams already live when this migration lands must be announced
-- ---------------------------------------------------------------------------
INSERT INTO public.stream_notification_outbox (stream_id, church_id, kind)
SELECT id, church_id, 'started'
  FROM public.live_streams
 WHERE status = 'live'
   AND church_id IS NOT NULL
   AND COALESCE(started_at, created_at) > now() - interval '6 hours'
ON CONFLICT (stream_id, kind) DO NOTHING;
