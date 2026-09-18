-- ============================================================================
-- 20261146_stream_config_platform_guard.sql
-- Server-side guard: church leaders may tune their stream FUNCTIONALITY, but
-- must never be able to change PLATFORM capacity/cost/pricing controls.
--
-- WHY: `church_stream_config` RLS lets any church leader UPDATE the row, which
-- also allowed them to self-grant unlimited minutes/viewers/retention/storage
-- (and to re-introduce the legacy per-church Cloudflare credentials). Those are
-- commercial platform settings owned by Church On App / COA staff.
--
-- This trigger enforces the split in the database (defence in depth on top of
-- the UI, which already hides the fields from non-staff):
--   * COA / superadmin  → full control.
--   * Service role / SQL→ untouched (auth.uid() IS NULL).
--   * Everyone else     → platform columns are forced to the PAID baseline on
--                         INSERT, and to their previous values on UPDATE.
-- ============================================================================

ALTER TABLE public.church_stream_config
  ADD COLUMN IF NOT EXISTS cloudflare_account_id text,
  ADD COLUMN IF NOT EXISTS cloudflare_api_token text;

CREATE OR REPLACE FUNCTION public.guard_church_stream_config_platform_cols()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  -- Service role / migrations / cron: no auth context → allow.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IN ('superadmin', 'super_admin', 'coa_employee', 'employee') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- Every church is on the paid plan (20261006); never let an insert
    -- silently downgrade a church to trial limits via the default columns.
    NEW.is_paid                  := true;
    NEW.max_minutes_per_week     := 480;
    NEW.max_viewers              := 1000;
    NEW.retention_days           := 90;
    NEW.max_storage_gb           := 10.0;
    NEW.max_stream_duration_sec  := 14400;
    NEW.max_quality              := 1080;
    NEW.cloudflare_account_id    := NULL;
    NEW.cloudflare_api_token     := NULL;
  ELSE
    NEW.is_paid                  := OLD.is_paid;
    NEW.max_minutes_per_week     := OLD.max_minutes_per_week;
    NEW.max_viewers              := OLD.max_viewers;
    NEW.retention_days           := OLD.retention_days;
    NEW.max_storage_gb           := OLD.max_storage_gb;
    NEW.max_stream_duration_sec  := OLD.max_stream_duration_sec;
    NEW.max_quality              := OLD.max_quality;
    NEW.cloudflare_account_id    := OLD.cloudflare_account_id;
    NEW.cloudflare_api_token     := OLD.cloudflare_api_token;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.guard_church_stream_config_platform_cols() FROM anon;
REVOKE EXECUTE ON FUNCTION public.guard_church_stream_config_platform_cols() FROM authenticated;

DROP TRIGGER IF EXISTS trg_guard_church_stream_config ON public.church_stream_config;
CREATE TRIGGER trg_guard_church_stream_config
  BEFORE INSERT OR UPDATE ON public.church_stream_config
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_church_stream_config_platform_cols();

-- ── R2 archive columns are public playback data ─────────────────────────────
-- The past-services (replay) list runs for signed-out viewers on the web too.
-- `20261144` granted these to `authenticated` only, which makes the replay
-- query fail with 42501 for anon and blank the list. These are public R2
-- playback URLs, so grant them to anon as well.
GRANT SELECT (archive_url, archive_status, archived_at, streaming_backend)
  ON public.live_streams TO anon;

