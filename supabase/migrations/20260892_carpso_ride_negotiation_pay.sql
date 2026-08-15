-- Carpso Ride / Delivery: negotiate BEFORE payment.
-- 1. ride_requests + delivery_requests get payment tracking (payment_ref from
--    the Lipila anchor, payment_status, paid_at) so a request can be created
--    unpaid and paid only after the fare is agreed.
-- 2. delivery_requests gets the same negotiation columns as ride_requests
--    (driver counter-offer back-and-forth before payment).
-- 3. pickup/dest labels so drivers see real addresses instead of coordinates.
-- 4. Platform-level ride payout number (superadmin/coa_employee only — tenants
--    never see ride money): platform_settings.ride_payout_mobile/network.
-- 5. payout_tasks + enqueue_payout_task accept the new 'ride_cut'/'delivery_cut'
--    sources (the COA cut of every ride/delivery is disbursed to the platform
--    number set by superadmin/coa_employee).

ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS payment_ref TEXT,
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid','pending','paid')),
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pickup_label TEXT,
  ADD COLUMN IF NOT EXISTS dest_label TEXT;

ALTER TABLE public.delivery_requests
  ADD COLUMN IF NOT EXISTS negotiation_status TEXT DEFAULT 'none'
    CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','accepted')),
  ADD COLUMN IF NOT EXISTS negotiated_fare DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS fare_locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_ref TEXT,
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid','pending','paid')),
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pickup_label TEXT,
  ADD COLUMN IF NOT EXISTS dest_label TEXT;

CREATE INDEX IF NOT EXISTS idx_delivery_requests_negotiation
  ON public.delivery_requests(negotiation_status)
  WHERE negotiation_status <> 'none';

-- Allow the platform ride/delivery cut as a payout source.
ALTER TABLE public.payout_tasks DROP CONSTRAINT IF EXISTS payout_tasks_source_check;
ALTER TABLE public.payout_tasks ADD CONSTRAINT payout_tasks_source_check
  CHECK (source IN ('giving','order','ride','delivery','escrow','manual','church_payout','ride_cut','delivery_cut'));

CREATE OR REPLACE FUNCTION public.enqueue_payout_task(
  p_source TEXT,
  p_source_ref TEXT,
  p_payment_ref TEXT,
  p_recipient_user_id UUID,
  p_recipient_phone TEXT,
  p_gross_amount NUMERIC
) RETURNS public.payout_tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_task public.payout_tasks;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_source NOT IN ('giving','order','ride','delivery','escrow','ride_cut','delivery_cut') THEN
    RAISE EXCEPTION 'Invalid settlement source';
  END IF;
  IF p_gross_amount IS NULL OR p_gross_amount <= 0 OR p_gross_amount > 100000 THEN
    RAISE EXCEPTION 'Invalid gross amount';
  END IF;
  IF p_recipient_user_id IS NOT NULL AND p_recipient_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot settle a payout to yourself';
  END IF;
  IF p_recipient_phone IS NOT NULL THEN
    p_recipient_phone := regexp_replace(p_recipient_phone, '\D', '', 'g');
    IF length(p_recipient_phone) = 9 THEN
      p_recipient_phone := '260' || p_recipient_phone;
    ELSIF length(p_recipient_phone) = 10 AND p_recipient_phone LIKE '0%' THEN
      p_recipient_phone := '260' || substring(p_recipient_phone FROM 2);
    END IF;
    IF p_recipient_phone = '' THEN
      p_recipient_phone := NULL;
    END IF;
  END IF;
  IF p_payment_ref IS NULL AND p_source_ref IS NULL THEN
    RAISE EXCEPTION 'A payment reference or source reference is required';
  END IF;

  INSERT INTO public.payout_tasks
    (user_id, source, source_ref, payment_ref, recipient_user_id, recipient_phone, gross_amount)
  VALUES
    (auth.uid(), p_source, p_source_ref, p_payment_ref, p_recipient_user_id, p_recipient_phone, p_gross_amount)
  ON CONFLICT (payment_ref, source, source_ref) DO NOTHING;

  SELECT * INTO v_task FROM public.payout_tasks
  WHERE user_id = auth.uid()
    AND source = p_source
    AND COALESCE(source_ref, '') = COALESCE(p_source_ref, '')
    AND COALESCE(payment_ref, '') = COALESCE(p_payment_ref, '')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_task IS NULL THEN
    RAISE EXCEPTION 'Could not enqueue settlement task';
  END IF;
  RETURN v_task;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC) FROM anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC) FROM PUBLIC;

-- Platform-level Carpso payout number. Set by superadmin/coa_employee ONLY.
-- Ride/delivery platform cuts are disbursed here; tenants never see these.
INSERT INTO public.platform_settings (key, value) VALUES
  ('ride_payout_mobile', ''),
  ('ride_payout_network', 'MTN')
ON CONFLICT (key) DO NOTHING;