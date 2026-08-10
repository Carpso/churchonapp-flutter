-- Carpso Ride fare negotiation columns.
-- Enables passenger-driver counter-offer flow (not just accept/decline).
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS negotiation_status TEXT DEFAULT 'none'
    CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','accepted')),
  ADD COLUMN IF NOT EXISTS negotiated_fare DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS fare_locked_at TIMESTAMPTZ;

-- Index for driver-side negotiation queries
CREATE INDEX IF NOT EXISTS idx_ride_requests_negotiation
  ON public.ride_requests(negotiation_status)
  WHERE negotiation_status <> 'none';
