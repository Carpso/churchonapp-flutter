-- 20261034: Carpso ride — fix driver visibility + missing fare columns + negotiation role
-- P0-01: drivers cannot see pending rides (SELECT RLS hole)
-- P1-11: offered_fare column may not exist on ride_requests (older DBs)
-- P0-07: role check 'driver' vs actual roles driver|rider mismatch

-- ─────────────────────────────────────────────────────────────
-- 1. Ensure ride_requests / delivery_requests have all fare/negotiation columns
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS offered_fare DOUBLE PRECISION;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS negotiated_fare DOUBLE PRECISION;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS negotiation_status TEXT DEFAULT 'none';
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS fare_locked_at TIMESTAMPTZ;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS negotiation_round INT NOT NULL DEFAULT 0;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS last_offer_by UUID;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS proposal_expires_at TIMESTAMPTZ;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS cancelled_by UUID;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS payment_ref TEXT;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid';
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS pickup_label TEXT;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS dest_label TEXT;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS preferences JSONB DEFAULT NULL;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS escrow_held BOOLEAN DEFAULT false;

-- Backfill offered_fare if legacy rows have NULL (guarded: column may not exist on older DBs)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ride_requests' AND column_name='estimated_fare') THEN
    EXECUTE 'UPDATE public.ride_requests SET offered_fare = COALESCE(offered_fare, estimated_fare, 0) WHERE offered_fare IS NULL';
  END IF;
EXCEPTION WHEN undefined_column THEN NULL; END $$;

ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS offered_fare DOUBLE PRECISION;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS negotiated_fare DOUBLE PRECISION;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS negotiation_status TEXT DEFAULT 'none';
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS fare_locked_at TIMESTAMPTZ;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS negotiation_round INT NOT NULL DEFAULT 0;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS last_offer_by UUID;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS proposal_expires_at TIMESTAMPTZ;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS cancelled_by UUID;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS payment_ref TEXT;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid';
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS pickup_label TEXT;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS dest_label TEXT;
ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS platform_fee NUMERIC DEFAULT 0.0;

-- Ensure negotiation_status CHECK includes all values needed for inDrive flow
ALTER TABLE public.ride_requests DROP CONSTRAINT IF EXISTS ride_requests_negotiation_status_check;
ALTER TABLE public.ride_requests ADD CONSTRAINT ride_requests_negotiation_status_check
  CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','passenger_countered','accepted'));

ALTER TABLE public.delivery_requests DROP CONSTRAINT IF EXISTS delivery_requests_negotiation_status_check;
ALTER TABLE public.delivery_requests ADD CONSTRAINT delivery_requests_negotiation_status_check
  CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','passenger_countered','accepted'));

-- ─────────────────────────────────────────────────────────────
-- 2. RLS: drivers must see pending rides (SELECT hole)
--    Existing policy requires auth.uid() = driver_id (NULL for pending) → 0 rows.
--    Add permissive pending SELECT for driver/rider roles.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Drivers can view pending ride requests" ON public.ride_requests;
CREATE POLICY "Drivers can view pending ride requests"
  ON public.ride_requests FOR SELECT TO authenticated
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('driver','rider','superadmin','coa_employee','employee'))
  );

DROP POLICY IF EXISTS "Drivers can view pending delivery requests" ON public.delivery_requests;
CREATE POLICY "Drivers can view pending delivery requests"
  ON public.delivery_requests FOR SELECT TO authenticated
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('driver','rider','superadmin','coa_employee','employee'))
  );

-- ─────────────────────────────────────────────────────────────
-- 3. RLS: negotiation UPDATE was driver-only, but couriers onboard as 'rider'
--    Broaden to both driver and rider roles (canWork = driver|rider)
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Drivers can negotiate pending ride requests" ON public.ride_requests;
CREATE POLICY "Drivers can negotiate pending ride requests"
  ON public.ride_requests FOR UPDATE TO authenticated
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('driver','rider','superadmin','coa_employee','employee'))
  );

DROP POLICY IF EXISTS "Drivers can negotiate pending delivery requests" ON public.delivery_requests;
CREATE POLICY "Drivers can negotiate pending delivery requests"
  ON public.delivery_requests FOR UPDATE TO authenticated
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('driver','rider','superadmin','coa_employee','employee'))
  );

-- ─────────────────────────────────────────────────────────────
-- 4. Indexes for pending-ride feeds
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ride_requests_pending ON public.ride_requests(status, created_at DESC) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_delivery_requests_pending ON public.delivery_requests(status, created_at DESC) WHERE status = 'pending';
