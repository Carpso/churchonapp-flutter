-- ============================================================================
-- 20261260 — STREAMING TRIAL MINUTES + PLAN GATES
--
-- PRODUCT MODEL (owner decision, 2026-10-31):
--   * Every new tenant automatically gets a GRANT of trial streaming minutes
--     (the "share of the trial minutes"). Minutes-based, NOT time-based: the
--     grant is consumed by broadcasting, not by calendar days.
--   * While trial minutes remain: live streaming + replay uploads included.
--   * When the grant is exhausted: live streaming and replay uploads are
--     BLOCKED until the church is on a plan (church_stream_config.is_paid=true,
--     flipped by COA when a church subscribes). Record-only capture stays free.
--   * 360p is the default capture quality for everyone; HD (720p) is a
--     paid-only option.
--
-- ENFORCEMENT: client checks are UX only. The teeth are three DB triggers:
--   1. BEFORE INSERT on live_streams       -> blocks live/scheduled creation
--                                             when the trial is exhausted.
--   2. BEFORE UPDATE OF archive_url        -> blocks attaching a replay when
--                                             the trial is exhausted.
--   3. BEFORE UPDATE OF status/ended_at    -> consumes minutes SERVER-SIDE on
--                                             every broadcast end (client stop,
--                                             cron expiry, archive sweep).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tunable grant size (COA-editable via platform_settings / admin UI)
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value)
VALUES ('streaming_trial_minutes', '120')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Trial ledger on the per-church streaming config
--    trial_minutes_total stays NULLable: the BEFORE INSERT trigger fills it
--    from platform_settings so the grant size is live-tunable without a
--    migration. 120 (two full services) is the fallback.
-- ---------------------------------------------------------------------------
ALTER TABLE public.church_stream_config
  ADD COLUMN IF NOT EXISTS trial_minutes_total integer,
  ADD COLUMN IF NOT EXISTS trial_minutes_used  integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION private.set_default_trial_minutes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v int;
BEGIN
  IF NEW.trial_minutes_total IS NULL THEN
    BEGIN
      SELECT NULLIF(btrim(value), '')::int INTO v
        FROM public.platform_settings
       WHERE key = 'streaming_trial_minutes'
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v := NULL; END;
    NEW.trial_minutes_total := GREATEST(0, COALESCE(v, 120));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stream_config_trial_default ON public.church_stream_config;
CREATE TRIGGER trg_stream_config_trial_default
BEFORE INSERT ON public.church_stream_config
FOR EACH ROW EXECUTE FUNCTION private.set_default_trial_minutes();

-- Backfill every existing church with its grant (fresh start of the model).
UPDATE public.church_stream_config
   SET trial_minutes_total = COALESCE(
         (SELECT NULLIF(btrim(s.value), '')::int
            FROM public.platform_settings s
           WHERE s.key = 'streaming_trial_minutes' AND s.value ~ '^\s*\d+\s*$'
           LIMIT 1),
         120)
 WHERE trial_minutes_total IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Everyone is on the trial model until they subscribe. COA flips
--    is_paid=true per church when the church's plan payment is confirmed.
-- ---------------------------------------------------------------------------
UPDATE public.church_stream_config SET is_paid = false WHERE is_paid;

-- ---------------------------------------------------------------------------
-- 4. live_streams: consumption marker + 'local' ingest mode (record-only)
-- ---------------------------------------------------------------------------
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS minutes_consumed boolean NOT NULL DEFAULT false;

ALTER TABLE public.live_streams
  DROP CONSTRAINT IF EXISTS live_streams_ingest_mode_check;
ALTER TABLE public.live_streams
  ADD CONSTRAINT live_streams_ingest_mode_check
  CHECK (ingest_mode IS NULL OR ingest_mode = ANY (ARRAY['rtmps'::text, 'whip'::text, 'local'::text]));

-- ---------------------------------------------------------------------------
-- 5. Server-side minute consumption on broadcast end.
--    Replaces the client self-reporting in endStream() (client-computed
--    minutes were trusted before). Fires on EVERY path that ends a broadcast:
--    the leader pressing STOP, cron expiry, the archive sweep.
--    Only CONFIRMED broadcasts (broadcast_started_at set) consume — an armed
--    row that never received media costs nothing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.consume_stream_minutes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start   timestamptz;
  v_end     timestamptz;
  v_minutes integer;
BEGIN
  -- Only a real transition into a finished state consumes anything.
  IF NEW.status NOT IN ('ended', 'archived') OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;
  -- Record-only sessions (ingest_mode='local') never touched the live pipe.
  IF NEW.ingest_mode = 'local' THEN RETURN NEW; END IF;
  IF COALESCE(NEW.minutes_consumed, false) THEN RETURN NEW; END IF;

  v_start := NEW.broadcast_started_at;
  IF v_start IS NULL THEN RETURN NEW; END IF; -- armed, never broadcast: free
  v_end := COALESCE(NEW.ended_at, now());
  IF v_end <= v_start THEN RETURN NEW; END IF;
  v_minutes := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_end - v_start)) / 60.0)::int);

  -- Weekly usage: server-derived truth (kept for the weekly fair-use cap).
  BEGIN
    PERFORM public.record_streaming_minutes(NEW.church_id, v_minutes);
  EXCEPTION WHEN OTHERS THEN
    NULL; -- bookkeeping must never block ending a stream
  END;

  -- Trial draw-down: only churches NOT on a paid plan consume their grant.
  BEGIN
    UPDATE public.church_stream_config
       SET trial_minutes_used = LEAST(COALESCE(trial_minutes_total, 0),
                                      trial_minutes_used + v_minutes),
           updated_at = now()
     WHERE church_id = NEW.church_id
       AND NOT COALESCE(is_paid, false);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  NEW.minutes_consumed := true;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_live_streams_consume_minutes ON public.live_streams;
CREATE TRIGGER trg_live_streams_consume_minutes
BEFORE UPDATE OF status, ended_at ON public.live_streams
FOR EACH ROW EXECUTE FUNCTION private.consume_stream_minutes();

-- ---------------------------------------------------------------------------
-- 6. Creation gate: an unpaid church with an exhausted grant cannot create a
--    live/scheduled stream. Service/cron writes (auth.uid() NULL) pass.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.gate_stream_creation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg record;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('live', 'scheduled') THEN RETURN NEW; END IF;
  IF COALESCE(private.is_platform_staff(), false) THEN RETURN NEW; END IF;

  SELECT COALESCE(is_paid, false) AS is_paid,
         COALESCE(trial_minutes_total, 0) AS total,
         trial_minutes_used
    INTO v_cfg
    FROM public.church_stream_config
   WHERE church_id = NEW.church_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'streaming_not_configured';
  END IF;
  IF NOT v_cfg.is_paid AND v_cfg.trial_minutes_used >= v_cfg.total THEN
    RAISE EXCEPTION 'trial_minutes_exhausted';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_live_streams_gate_creation ON public.live_streams;
CREATE TRIGGER trg_live_streams_gate_creation
BEFORE INSERT ON public.live_streams
FOR EACH ROW EXECUTE FUNCTION private.gate_stream_creation();

-- ---------------------------------------------------------------------------
-- 7. Upload gate: attaching a replay (archive_url) requires a plan OR trial
--    minutes remaining. Record-only capture stays free; only the upload is
--    plan-gated (owner decision). Service/cron archive sweeps pass.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.gate_recording_upload()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg record;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF COALESCE(private.is_platform_staff(), false) THEN RETURN NEW; END IF;
  -- Only gate the moment a recording URL is FIRST attached.
  IF NEW.archive_url IS NULL OR btrim(NEW.archive_url) = ''
     OR NEW.archive_url IS NOT DISTINCT FROM OLD.archive_url THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(is_paid, false) AS is_paid,
         COALESCE(trial_minutes_total, 0) AS total,
         trial_minutes_used
    INTO v_cfg
    FROM public.church_stream_config
   WHERE church_id = NEW.church_id;
  IF FOUND AND NOT v_cfg.is_paid AND v_cfg.trial_minutes_used >= v_cfg.total THEN
    RAISE EXCEPTION 'upload_requires_plan';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_live_streams_gate_upload ON public.live_streams;
CREATE TRIGGER trg_live_streams_gate_upload
BEFORE UPDATE OF archive_url ON public.live_streams
FOR EACH ROW EXECUTE FUNCTION private.gate_recording_upload();

-- ---------------------------------------------------------------------------
-- 8. Entitlement RPC for the studio UI (quality option, upload gate, banners).
--    Caller must belong to the church or be platform staff.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_streaming_entitlement(p_church_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c          public.church_stream_config%ROWTYPE;
  v_caller   text;
  v_week_use integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT COALESCE(private.is_platform_staff(), false) THEN
    SELECT p.tenant_id INTO v_caller FROM public.profiles p WHERE p.id = auth.uid();
    IF v_caller IS NULL OR v_caller <> p_church_id::text THEN
      RAISE EXCEPTION 'not_your_church';
    END IF;
  END IF;

  SELECT * INTO c FROM public.church_stream_config WHERE church_id = p_church_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'configured', false, 'is_paid', false,
      'trial_total', 0, 'trial_used', 0, 'trial_remaining', 0,
      'can_stream', false, 'can_upload', false, 'can_hd', false,
      'weekly_used', 0, 'weekly_max', 0);
  END IF;

  SELECT COALESCE(SUM(minutes_used), 0)::int INTO v_week_use
    FROM public.streaming_usage
   WHERE church_id = p_church_id
     AND week_start = date_trunc('week', now())::date;

  RETURN jsonb_build_object(
    'configured', true,
    'is_paid', c.is_paid,
    'trial_total', COALESCE(c.trial_minutes_total, 0),
    'trial_used', c.trial_minutes_used,
    'trial_remaining', GREATEST(0, COALESCE(c.trial_minutes_total, 0) - c.trial_minutes_used),
    'can_stream', c.is_paid OR c.trial_minutes_used < COALESCE(c.trial_minutes_total, 0),
    'can_upload', c.is_paid OR c.trial_minutes_used < COALESCE(c.trial_minutes_total, 0),
    'can_hd', c.is_paid,
    'weekly_used', v_week_use,
    'weekly_max', c.max_minutes_per_week);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_streaming_entitlement(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_streaming_entitlement(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. Verification
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_fail text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'church_stream_config' AND column_name = 'trial_minutes_total') THEN
    v_fail := v_fail || ' trial_column;';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'get_streaming_entitlement') <> 1 THEN
    v_fail := v_fail || ' entitlement_rpc;';
  END IF;
  IF (SELECT count(*) FROM pg_trigger
       WHERE tgrelid = 'public.live_streams'::regclass AND NOT tgisinternal
         AND tgname IN ('trg_live_streams_consume_minutes',
                        'trg_live_streams_gate_creation',
                        'trg_live_streams_gate_upload')) <> 3 THEN
    v_fail := v_fail || ' triggers;';
  END IF;
  IF EXISTS (SELECT 1 FROM church_stream_config WHERE is_paid) THEN
    v_fail := v_fail || ' is_paid_not_reset;';
  END IF;
  IF EXISTS (SELECT 1 FROM church_stream_config WHERE trial_minutes_total IS NULL) THEN
    v_fail := v_fail || ' grant_backfill;';
  END IF;
  IF v_fail <> '' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED:%', v_fail;
  END IF;
  RAISE NOTICE 'streaming trial minutes: all checks passed';
END;
$$;
