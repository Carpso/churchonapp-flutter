-- Proof of delivery / completion: photo + GPS captured by the courier or driver
-- at the drop-off point, so last-mile handovers are evidenced and auditable.

ALTER TABLE public.delivery_requests
  ADD COLUMN IF NOT EXISTS proof_photo_url text,
  ADD COLUMN IF NOT EXISTS proof_lat       double precision,
  ADD COLUMN IF NOT EXISTS proof_lng       double precision,
  ADD COLUMN IF NOT EXISTS proof_note      text,
  ADD COLUMN IF NOT EXISTS delivered_at    timestamptz;

ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS proof_photo_url text,
  ADD COLUMN IF NOT EXISTS proof_lat       double precision,
  ADD COLUMN IF NOT EXISTS proof_lng       double precision,
  ADD COLUMN IF NOT EXISTS proof_note      text,
  ADD COLUMN IF NOT EXISTS completed_at    timestamptz;

COMMENT ON COLUMN public.delivery_requests.proof_photo_url IS
  'R2 URL of the courier''s drop-off photo (proof of delivery).';
COMMENT ON COLUMN public.delivery_requests.proof_lat IS
  'GPS latitude where the delivery was handed over / left.';
