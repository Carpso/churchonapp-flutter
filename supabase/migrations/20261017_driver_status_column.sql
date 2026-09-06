-- ═══════════════════════════════════════════════════════════════
-- Driver dashboard fixes
-- 1. profiles.driver_status does NOT exist, but the driver dashboard
--    selects/updates it — the whole dashboard failed to load and the
--    online/offline toggle silently errored. Add the column.
-- 2. Driver earnings read `deliveries.fee` (no such column) and
--    `ride_bookings` (no such table). Real sources are
--    `delivery_requests` / `ride_requests` (see client fix).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS driver_status TEXT NOT NULL DEFAULT 'offline';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_driver_status_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_driver_status_check
      CHECK (driver_status IN ('online', 'offline', 'busy'));
  END IF;
END $$;
