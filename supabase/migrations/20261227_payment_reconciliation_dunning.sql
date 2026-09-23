-- ═══════════════════════════════════════════════════════════════════════════════
-- PAYMENT RECONCILIATION + PAYEE DUNNING (ported from chisomo/Kingdom Sponsor)
--
-- Three gaps this closes, all server-side and invariant-preserving:
--   A. Payout reconciliation — a payout that Lipila ACCEPTED but whose webhook
--      was lost stayed `processing` forever (the cron only selects `pending`).
--      `next_attempt_at` adds chisomo's retry backoff, and the settlement engine
--      now re-checks Lipila's disbursement status for in-flight tasks.
--   B. Platform-fee ledger — chisomo's `fee_sweeps`. COA's payout cut was only
--      netted off the host amount and never tracked or swept. This adds the
--      ledger + a reconciliation RPC.
--   C. Recurring-pledge auto-charge (collection-from-payees) — chisomo's
--      `recurring_pledges` dunning. COA pledges were a manual installment
--      tracker with a client-side reminder only. Now the server can charge a
--      due pledge (amount derived server-side from `pledges.amount_per_cycle`).
--
-- Invariants preserved (see PAYMENTS.md §9):
--   * The client NEVER decides payer/payee/amount — the charge amount is read
--     from `pledges.amount_per_cycle`, the recipient chain is unchanged.
--   * No `coa_payments` row is ever created from a payout webhook.
--   * Ledgers are service-role write only; clients read their own rows.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── A. Retry backoff on the payout queue ────────────────────────────────────────
ALTER TABLE public.payout_tasks
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS payout_tasks_retry_idx
  ON public.payout_tasks (status, next_attempt_at);

-- ── B. Platform-fee sweep ledger (chisomo `fee_sweeps`) ─────────────────────────
CREATE TABLE IF NOT EXISTS public.fee_sweeps (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             TEXT NOT NULL DEFAULT 'payout_fee'
    CHECK (kind IN ('payout_fee','admin_withdraw','manual')),
  amount           NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  lipila_reference TEXT,
  status           TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','success','failed')),
  last_error       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS fee_sweeps_status_idx ON public.fee_sweeps (status, created_at);

ALTER TABLE public.fee_sweeps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fee_sweeps_select" ON public.fee_sweeps;
CREATE POLICY "fee_sweeps_select" ON public.fee_sweeps FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop')
  )
);
-- No client INSERT/UPDATE/DELETE — written by the Edge Functions (service key).

-- Platform-fee reconciliation: payout-side fees earned (COA payout cut on every
-- completed church withdrawal) minus what has already been swept to the COA
-- settlement number. Collection-side fees are charged on top of the gift at
-- collection time and remain in the merchant wallet (not tracked per row yet).
CREATE OR REPLACE FUNCTION public.get_platform_fee_summary()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_earned NUMERIC := 0;
  v_settled NUMERIC := 0;
  v_collected NUMERIC := 0;
  v_paid_out NUMERIC := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop')
  ) THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT COALESCE(SUM(w.coa_fee), 0) INTO v_earned
  FROM public.church_withdrawals w
  WHERE w.status IN ('processing','paid');

  SELECT COALESCE(SUM(s.amount), 0) INTO v_settled
  FROM public.fee_sweeps s
  WHERE s.status IN ('pending','success');

  SELECT COALESCE(SUM((c.amount)::numeric), 0) INTO v_collected
  FROM public.coa_payments c
  WHERE c.status IN ('approved','completed','confirmed','settled');

  SELECT COALESCE(SUM(t.net_amount), 0) INTO v_paid_out
  FROM public.payout_tasks t
  WHERE t.status = 'paid';

  RETURN jsonb_build_object(
    'payout_fees_earned', v_earned,
    'payout_fees_settled', v_settled,
    'payout_fees_pending', GREATEST(0, v_earned - v_settled),
    'total_collected', v_collected,
    'total_paid_out', v_paid_out
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_platform_fee_summary() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_platform_fee_summary() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_platform_fee_summary() TO authenticated;

-- ── C. Recurring-pledge auto-charge (chisomo `recurring_pledges` dunning) ────────
ALTER TABLE public.pledges
  ADD COLUMN IF NOT EXISTS auto_charge     BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS day_of_month    INT CHECK (day_of_month BETWEEN 1 AND 28),
  ADD COLUMN IF NOT EXISTS last_charged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_charge_ref TEXT,
  ADD COLUMN IF NOT EXISTS next_charge_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS pledges_due_idx
  ON public.pledges (auto_charge, next_charge_at)
  WHERE status = 'active';

-- Which pledges are due to be charged right now? Service-role only — this is
-- the cron's work list. The amount is read from the pledge row, never supplied.
CREATE OR REPLACE FUNCTION public.due_pledges_for_charge(p_limit INTEGER DEFAULT 50)
RETURNS TABLE (
  pledge_id UUID,
  user_id UUID,
  tenant_id UUID,
  phone TEXT,
  amount NUMERIC,
  category TEXT,
  frequency TEXT,
  day_of_month INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT pl.id,
         pl.user_id,
         pl.tenant_id,
         p.phone_number::text AS phone,
         pl.amount_per_cycle AS amount,
         pl.category,
         pl.frequency,
         pl.day_of_month
  FROM public.pledges pl
  JOIN public.profiles p ON p.id = pl.user_id
  WHERE pl.status = 'active'
    AND pl.auto_charge = true
    AND pl.paid_amount < pl.total_amount
    AND p.phone_number IS NOT NULL
    AND (
      pl.next_charge_at IS NULL
      OR pl.next_charge_at <= now()
    )
  ORDER BY pl.next_charge_at NULLS FIRST, pl.created_at ASC
  LIMIT GREATEST(1, LEAST(p_limit, 200));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.due_pledges_for_charge(INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.due_pledges_for_charge(INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.due_pledges_for_charge(INTEGER) TO service_role;

-- Record the outcome of one auto-charge attempt. On success the paid amount is
-- credited and the next charge is scheduled by frequency; on failure the charge
-- is retried on the next cron pass (the pledge itself is never failed).
CREATE OR REPLACE FUNCTION public.record_pledge_charge(
  p_pledge_id UUID,
  p_payment_ref TEXT,
  p_status TEXT DEFAULT 'initiated'
) RETURNS public.pledges
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pledge public.pledges;
  v_next TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_pledge FROM public.pledges WHERE id = p_pledge_id;
  IF v_pledge IS NULL THEN
    RAISE EXCEPTION 'Pledge not found';
  END IF;

  IF lower(COALESCE(p_status, '')) = 'success' THEN
    UPDATE public.pledges
    SET paid_amount = LEAST(total_amount, paid_amount + amount_per_cycle),
        status = CASE WHEN paid_amount + amount_per_cycle >= total_amount
                      THEN 'completed' ELSE status END,
        last_charged_at = now(),
        last_charge_ref = p_payment_ref,
        next_charge_at = CASE frequency
                           WHEN 'weekly'    THEN now() + interval '7 days'
                           WHEN 'quarterly' THEN now() + interval '3 months'
                           ELSE now() + interval '1 month'
                         END,
        updated_at = now()
    WHERE id = p_pledge_id
    RETURNING * INTO v_pledge;
  ELSE
    -- initiated / failed: remember the reference and retry later. Never fail
    -- the pledge because a payment attempt did not go through.
    UPDATE public.pledges
    SET last_charge_ref = p_payment_ref,
        next_charge_at = now() + interval '1 day',
        updated_at = now()
    WHERE id = p_pledge_id
    RETURNING * INTO v_pledge;
  END IF;

  RETURN v_pledge;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_pledge_charge(UUID, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_pledge_charge(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.record_pledge_charge(UUID, TEXT, TEXT) TO service_role;

-- ── D. Leader-facing church earnings (chisomo host dashboard parity) ────────────
-- A church leader sees ONLY their own church's withdrawable balance + ledger,
-- instead of the platform-wide admin list. Fails closed (no tenant -> empty).
CREATE OR REPLACE FUNCTION public.get_my_church_earnings()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tenant TEXT;
  v_balance JSONB;
  v_history JSONB;
BEGIN
  SELECT p.tenant_id::text INTO v_tenant
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF v_tenant IS NULL OR v_tenant = '' THEN
    RETURN jsonb_build_object('withdrawable', 0, 'gross_collected', 0,
                              'in_flight_withdrawals', 0, 'withdrawals', '[]'::jsonb);
  END IF;

  SELECT jsonb_build_object(
           'withdrawable', COALESCE(b.withdrawable, 0),
           'gross_collected', COALESCE(b.gross_collected, 0),
           'committed_giving', COALESCE(b.committed_giving, 0),
           'in_flight_withdrawals', COALESCE(b.in_flight_withdrawals, 0),
           'recipient_phone', b.treasurer_phone
         )
    INTO v_balance
  FROM public._church_withdrawable_balances_svc() b
  WHERE b.church_id = v_tenant
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(row_to_json(w) ORDER BY w.created_at DESC), '[]'::jsonb)
    INTO v_history
  FROM (
    SELECT id, gross_amount, net_amount, coa_fee, lipila_fee, recipient_phone,
           lipila_reference, status, created_at, processed_at
    FROM public.church_withdrawals
    WHERE church_id = v_tenant
    ORDER BY created_at DESC
    LIMIT 50
  ) w;

  RETURN COALESCE(v_balance, jsonb_build_object('withdrawable', 0, 'gross_collected', 0))
         || jsonb_build_object('withdrawals', v_history);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_church_earnings() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_church_earnings() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_my_church_earnings() TO authenticated;

-- ── Config keys ─────────────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, updated_at) VALUES
  ('payout_retry_backoff_minutes', '30', now()),
  ('platform_fee_sweep_min_kwacha', '50', now()),
  ('coa_settlement_phone', '', now())
ON CONFLICT (key) DO NOTHING;
