-- ═══════════════════════════════════════════════════════════════════════════════
-- SERVER-SIDE SETTLEMENT (2026-08-13)
-- Replaces client-initiated lipila-payout calls with a server-side settlement
-- queue. Clients ENQUEUE payout tasks; the server executes them when the
-- underlying collection is confirmed by the Lipila webhook (or via the
-- lps-settle cron as retry/reliability).
--
-- Why this is safe:
--   * payout_tasks.status transitions are service-role only (no client UPDATE).
--   * enqueue_payout_task validates source/amount/phone and blocks self-settlement.
--   * The server re-derives recipient + gross from DB facts at execution:
--       giving  -> church treasurer_phone (from payer's tenant), gross capped by
--                  the webhook-confirmed collection amount
--       order   -> seller profile phone (recipient_user_id), capped by collection
--       ride    -> ride_requests.driver_id (owner check) + fare * (1 - cut)
--       delivery-> delivery_requests.driver_id + offered_fare * (1 - cut)
--       escrow  -> delivery_requests.vendor_phone + item_price
--   * Payouts are atomic (status 'pending' -> 'processing' claim + payout_ref)
--     so a task can never be paid twice.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── payout_tasks ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payout_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('giving','order','ride','delivery','escrow','manual')),
  source_ref TEXT,
  payment_ref TEXT,
  recipient_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  recipient_phone TEXT,
  gross_amount NUMERIC(12,2) NOT NULL,
  net_amount NUMERIC(12,2),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','paid','failed','cancelled')),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  payout_ref TEXT,
  tenant_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payout_tasks_unique_anchor UNIQUE (payment_ref, source, source_ref)
);

CREATE INDEX IF NOT EXISTS payout_tasks_pending_idx ON public.payout_tasks (status, created_at);
CREATE INDEX IF NOT EXISTS payout_tasks_payment_ref_idx ON public.payout_tasks (payment_ref);
CREATE INDEX IF NOT EXISTS payout_tasks_source_ref_idx ON public.payout_tasks (source, source_ref);

ALTER TABLE public.payout_tasks ENABLE ROW LEVEL SECURITY;

-- Clients may only see their own queued tasks (and the ledger roles).
DROP POLICY IF EXISTS "payout_tasks_select" ON public.payout_tasks;
CREATE POLICY "payout_tasks_select" ON public.payout_tasks FOR SELECT USING (
  auth.uid() = user_id
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop'))
);

-- No client INSERT/UPDATE/DELETE policies — creation goes through
-- enqueue_payout_task() (SECURITY DEFINER). Status transitions are
-- service-role only (the Edge Functions run with the service key).

-- ── enqueue_payout_task ─────────────────────────────────────────────────────────
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
  IF p_source NOT IN ('giving','order','ride','delivery','escrow') THEN
    RAISE EXCEPTION 'Invalid settlement source';
  END IF;
  IF p_gross_amount IS NULL OR p_gross_amount <= 0 OR p_gross_amount > 100000 THEN
    RAISE EXCEPTION 'Invalid gross amount';
  END IF;
  IF p_recipient_user_id IS NOT NULL AND p_recipient_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot settle a payout to yourself';
  END IF;
  -- Recipient phone is a HINT only — the engine re-derives the true recipient
  -- from server-side records (church treasurer, seller profile, driver id) at
  -- execution time. Normalize common local formats; never reject the enqueue
  -- over formatting, otherwise rides/deliveries/orders with local-format
  -- numbers would silently lose their payout task.
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
