-- ============================================================================
-- STREAM NOTIFICATION PIPELINE — end-to-end integration test.
--
-- Runs the real production path (triggers + dispatch_stream_notifications)
-- inside a transaction that is ROLLED BACK, so it writes no notifications,
-- sends no pushes, and leaves no rows behind.
--
-- `private.push_to_users` is swapped for a collector so we can assert exactly
-- WHO would have been pushed to, without ever calling FCM.
--
-- Every assertion is folded into ONE result set because the Supabase CLI only
-- prints the final statement's output.
-- ============================================================================
BEGIN;

CREATE TEMP TABLE _push_capture (
  user_ids uuid[], title text, body text, type text, channel text, ref text
);

CREATE OR REPLACE FUNCTION private.push_to_users(
  p_user_ids uuid[], p_title text, p_body text, p_type text,
  p_channel text DEFAULT NULL, p_reference_id text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _push_capture VALUES (p_user_ids, p_title, p_body, p_type, p_channel, p_reference_id);
END;
$$;

CREATE TEMP TABLE _result (step text, detail text, expected text, pass boolean);

DO $$
DECLARE
  v_tenant uuid := gen_random_uuid();
  v_stream uuid := gen_random_uuid();
  v_ids    uuid[];
  v_broad  uuid; v_m1 uuid; v_m2 uuid; v_m3 uuid;
  v_n      bigint;
  v_ok     boolean;
  v_txt    text;
BEGIN
  -- tenants.id and churches.id share the SAME uuid in this schema (36/36 rows
  -- resolve to both), so one id is used for both, exactly like seeded data.
  INSERT INTO public.tenants (id, name, type) VALUES (v_tenant, 'ZZ Stream Test Tenant', 'church');
  INSERT INTO public.churches (id, name, slug, tenant_id, is_verified)
    VALUES (v_tenant, 'ZZ Stream Test Church', 'zz-stream-test-church', v_tenant, true);

  -- Borrow 4 EXISTING profiles: profiles.id is an FK to the users table, so
  -- synthetic ids cannot be inserted. The rollback restores their tenancy.
  SELECT array_agg(id) INTO v_ids FROM (SELECT id FROM public.profiles ORDER BY id LIMIT 4) s;
  v_broad := v_ids[1]; v_m1 := v_ids[2]; v_m2 := v_ids[3]; v_m3 := v_ids[4];
  UPDATE public.profiles SET tenant_id = v_tenant::text
   WHERE id IN (v_broad, v_m1, v_m2, v_m3);

  ---------------------------------------------------------------- STEP 1
  -- Creating the row with status='live' must NOT announce anything: no encoder
  -- has published yet. This is the bug 20261241 exists to fix.
  INSERT INTO public.live_streams
    (id, church_id, title, status, streaming_backend, ingest_mode, created_by)
  VALUES (v_stream, v_tenant, 'ZZ Sunday Service', 'live', 'cloudflare', 'rtmps', v_broad);

  SELECT count(*) INTO v_n FROM public.stream_notification_outbox WHERE stream_id = v_stream;
  INSERT INTO _result VALUES
    ('1 armed-but-not-airing queues nothing', 'outbox=' || v_n, '0', v_n = 0);

  ---------------------------------------------------------------- STEP 2
  -- Media confirmed flowing -> exactly one 'started' outbox row.
  UPDATE public.live_streams SET broadcast_started_at = now() WHERE id = v_stream;
  SELECT count(*) INTO v_n FROM public.stream_notification_outbox
   WHERE stream_id = v_stream AND kind = 'started';
  INSERT INTO _result VALUES
    ('2 broadcast_started_at queues started', 'rows=' || v_n, '1', v_n = 1);

  ---------------------------------------------------------------- STEP 3
  PERFORM public.dispatch_stream_notifications(10);

  -- 3 members notified, broadcaster excluded.
  SELECT count(*) INTO v_n FROM public.notifications n
   WHERE n.reference_id = v_stream::text AND n.type = 'stream_started';
  INSERT INTO _result VALUES
    ('3 members notified (broadcaster excluded)', 'rows=' || v_n, '3', v_n = 3);

  -- Broadcaster must NOT be among the recipients.
  SELECT count(*) INTO v_n FROM public.notifications n
   WHERE n.reference_id = v_stream::text AND n.user_id = v_broad;
  INSERT INTO _result VALUES
    ('3b broadcaster NOT notified', 'rows=' || v_n, '0', v_n = 0);

  -- Push fan-out shape: right type, right channel, 3 recipients in one chunk.
  SELECT count(*) INTO v_n FROM _push_capture WHERE type = 'stream_started';
  v_ok := v_n = 1;
  INSERT INTO _result VALUES
    ('4a one chunked push call', 'calls=' || v_n, '1', v_ok);

  SELECT coalesce(max(array_length(user_ids,1)), 0) INTO v_n FROM _push_capture
   WHERE type = 'stream_started';
  INSERT INTO _result VALUES
    ('4b all 3 members in the push', 'users=' || v_n, '3', v_n = 3);

  SELECT count(*) INTO v_n FROM _push_capture
   WHERE type = 'stream_started' AND channel = 'coa_live_stream';
  INSERT INTO _result VALUES
    ('4c push uses the live-stream channel', 'channel_ok=' || v_n, '1', v_n = 1);

  ---------------------------------------------------------------- STEP 5
  -- Idempotency: a second dispatch must send nothing more.
  PERFORM public.dispatch_stream_notifications(10);
  SELECT count(*) INTO v_n FROM _push_capture;
  INSERT INTO _result VALUES
    ('5 re-dispatch is idempotent (no double notify)', 'pushes=' || v_n, '1', v_n = 1);

  ---------------------------------------------------------------- STEP 6
  -- End of service -> 'ended' announcement, mentioning the recording.
  UPDATE public.live_streams
     SET status = 'ended', ended_at = now(),
         recording_hls_url = 'https://example.com/rec.m3u8'
   WHERE id = v_stream;
  SELECT count(*) INTO v_n FROM public.stream_notification_outbox
   WHERE stream_id = v_stream AND kind = 'ended';
  INSERT INTO _result VALUES
    ('6 end queues ended', 'rows=' || v_n, '1', v_n = 1);

  PERFORM public.dispatch_stream_notifications(10);
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE reference_id = v_stream::text AND type = 'stream_ended';
  INSERT INTO _result VALUES
    ('7 members told the service ended', 'rows=' || v_n, '3', v_n = 3);

  SELECT body INTO v_txt FROM _push_capture WHERE type = 'stream_ended' LIMIT 1;
  INSERT INTO _result VALUES
    ('8 ended copy mentions the recording', left(v_txt, 46), 'promises replay', v_txt ILIKE '%recording is now available%');

  ---------------------------------------------------------------- STEP 9
  -- WHIP must never be chased for a recording that cannot exist.
  UPDATE public.live_streams
     SET status = 'ended', ingest_mode = 'whip', ended_at = now()
   WHERE id = v_stream;
  SELECT count(*) INTO v_n FROM public.live_streams
   WHERE id = v_stream AND archive_status = 'not_applicable';
  INSERT INTO _result VALUES
    ('9 WHIP broadcast marked unrecordable', 'archive_status hits=' || v_n, '1', v_n = 1);
END $$;

-- A single result set so the Supabase CLI shows everything.
SELECT step, detail, expected,
       CASE WHEN pass THEN 'PASS' ELSE '** FAIL **' END AS result
  FROM _result
 UNION ALL
 SELECT '== TOTAL ==', count(*)::text || ' assertions',
        count(*) FILTER (WHERE pass)::text || ' passed / ' || count(*) FILTER (WHERE NOT pass)::text || ' failed',
        CASE WHEN count(*) FILTER (WHERE NOT pass) = 0 THEN 'ALL GREEN' ELSE 'FAILURES' END
   FROM _result
 ORDER BY step;



ROLLBACK;
