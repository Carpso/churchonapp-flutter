-- ═══════════════════════════════════════════════════════════════════════════
-- 20261239 — FIX DRIVER LOCATION WRITES (the two errors in the live console)
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. `23502 null value in column "type" ... violates not-null constraint`
--    `TransportService.updateLocation` upserts into `ride_registrations` with
--    only {user_id, lat, lng, updated_at}. `type` is NOT NULL with no default,
--    so EVERY 30s heartbeat for EVERY member on work mode failed. The table is
--    a "who is on the road" registry, so the honest value is 'rider' for a
--    member and 'driver' for a driver. We give the column a DEFAULT and a
--    CHECK so the data is meaningful, rather than silently writing a lie.
--
-- 2. `42501 new row violates row-level security policy ... driver_locations`
--    The INSERT policy required the caller's role to be one of
--    driver/rider/superadmin/coa_employee. Any other signed-in member on work
--    mode was rejected, so member GPS heartbeats were lost — which also starved
--    the crowd-sourced traffic overlay of its biggest data source.
--    We widen it to: a member may write their OWN row (driver_id = auth.uid()).
--    It is still self-only, so nobody can move anybody else's dot.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. ride_registrations.type ─────────────────────────────────────────────
ALTER TABLE public.ride_registrations
  ALTER COLUMN type SET DEFAULT 'rider';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ride_registrations_type_check'
  ) THEN
    ALTER TABLE public.ride_registrations
      ADD CONSTRAINT ride_registrations_type_check
      CHECK (type IN ('driver','rider','admin','staff','other'));
  END IF;
END $$;

-- Backstop: nothing should be null even if a client omits the column.
UPDATE public.ride_registrations
   SET type = 'rider'
 WHERE type IS NULL;

-- ── 2. driver_locations INSERT policy ─────────────────────────────────────
DROP POLICY IF EXISTS driver_locations_owner_insert ON public.driver_locations;

-- A signed-in member may record a position for THEMSELVES only. We no longer
-- require a transport role, because work mode is available to every member and
-- their speed is exactly the signal the traffic overlay needs.
CREATE POLICY driver_locations_self_insert ON public.driver_locations
  FOR INSERT TO authenticated
  WITH CHECK (driver_id = auth.uid());

-- Reads: a rider must be able to see nearby drivers to be matched, and the
-- map shows driver dots, so keep the existing permissive SELECT.
