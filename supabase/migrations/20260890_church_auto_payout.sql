-- ═══════════════════════════════════════════════════════════════════════════════
-- CHURCH AUTO-PAYOUT (2026-08-13)
-- Mirrors the Kingdom Sponsor (chisomo) host payout model inside Church On App:
-- a church's withdrawable giving balance is computed server-side from CONFIRMED
-- collections minus anything already committed to a payout (per-transaction
-- giving tasks or an in-flight church withdrawal). The lps-settle cron (and the
-- Lipila webhook) call enqueueChurchAutoPayouts(): when a church's balance
-- crosses `church_payout_min_kwacha`, a church_withdrawals row + a
-- payout_tasks('church_payout') task are created, and the shared settlement
-- engine disburses to the church treasurer phone automatically.
--
-- Why this is safe:
--   * Withdrawable balance is re-derived from DB facts every time (confirmed
--     coa_payments for the church MINUS committed giving tasks MINUS in-flight
--     withdrawals). A client can never inject an amount.
--   * One in-flight withdrawal per church (partial unique index) + the atomic
--     'pending' -> 'processing' claim in the settlement engine prevent
--     double-pay from concurrent cron/webhook/admin triggers.
--   * church_withdrawals is INSERT/UPDATE service-role only (RLS = select to
--     superadmin + church leadership); clients only READ.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── church_withdrawals ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.church_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id TEXT NOT NULL,                -- churches.id::text (uuid or seed id like 'zm_1')
  church_name TEXT,
  gross_amount NUMERIC(12,2) NOT NULL,    -- withdrawable balance at enqueue time
  lipila_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  coa_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount NUMERIC(12,2),
  recipient_phone TEXT NOT NULL,          -- church treasurer_phone (normalized)
  lipila_reference TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','processing','paid','failed','cancelled')),
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS church_withdrawals_status_idx ON public.church_withdrawals (status, created_at);
CREATE INDEX IF NOT EXISTS church_withdrawals_church_idx ON public.church_withdrawals (church_id, created_at);

-- Atomic guard: at most ONE in-flight withdrawal per church, so concurrent
-- cron / webhook / admin triggers can never start a second payout.
CREATE UNIQUE INDEX IF NOT EXISTS church_withdrawals_single_inflight
  ON public.church_withdrawals (church_id)
  WHERE status IN ('pending','processing');

ALTER TABLE public.church_withdrawals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "church_withdrawals_select" ON public.church_withdrawals;
CREATE POLICY "church_withdrawals_select" ON public.church_withdrawals FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop')
  )
);

-- No client INSERT/UPDATE/DELETE policies — the ledger is written by the
-- Edge Functions with the service key only.

-- ── payout_tasks: allow the church_payout source, user_id optional ────────────
-- (church_payout tasks are enqueued by the server, not by a user.)
ALTER TABLE public.payout_tasks DROP CONSTRAINT IF EXISTS payout_tasks_source_check;
ALTER TABLE public.payout_tasks ADD CONSTRAINT payout_tasks_source_check
  CHECK (source IN ('giving','order','ride','delivery','escrow','manual','church_payout'));
ALTER TABLE public.payout_tasks ALTER COLUMN user_id DROP NOT NULL;

-- ── Withdrawable balances (server-side core, service-role only) ───────────────
-- No auth gate: called by the Edge Functions (service key) and internally by the
-- role-gated wrapper + the auto-payout enqueue function. REVOKEd from every role
-- except the function owner (postgres/service_role), so clients can never run it.
CREATE OR REPLACE FUNCTION public._church_withdrawable_balances_svc()
RETURNS TABLE (
  church_id TEXT,
  church_name TEXT,
  treasurer_phone TEXT,
  gross_collected NUMERIC,
  committed_giving NUMERIC,
  in_flight_withdrawals NUMERIC,
  withdrawable NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH confirmed AS (
    SELECT c.metadata->>'tenant_id' AS church_id,
           COALESCE(SUM((c.amount)::numeric), 0) AS gross
    FROM public.coa_payments c
    WHERE c.status IN ('approved','completed','confirmed','settled')
      AND c.metadata->>'tenant_id' IS NOT NULL
      -- Only count giving confirmed after the server-side settlement rollout
      -- (2026-08-13), OR payments that already have a payout task. This keeps
      -- legacy collections that were paid out by the old client-side path from
      -- ever being paid a second time through the aggregate auto-payout.
      AND (c.created_at >= TIMESTAMPTZ '2026-08-13 00:00:00+00'
           OR EXISTS (
             SELECT 1 FROM public.payout_tasks t
             WHERE t.payment_ref = c.payment_ref AND t.source = 'giving'
           ))
    GROUP BY 1
  ),
  committed AS (
    SELECT p.metadata->>'tenant_id' AS church_id,
           COALESCE(SUM(t.gross_amount), 0) AS gross
    FROM public.payout_tasks t
    JOIN public.coa_payments p ON p.payment_ref = t.payment_ref
    WHERE t.source = 'giving'
      AND t.status IN ('pending','processing','paid')
      AND p.metadata->>'tenant_id' IS NOT NULL
    GROUP BY 1
  ),
  inflight AS (
    SELECT w.church_id,
           COALESCE(SUM(w.gross_amount), 0) AS gross
    FROM public.church_withdrawals w
    WHERE w.status IN ('pending','processing','paid')
    GROUP BY 1
  )
  SELECT
    ch.id::text AS church_id,
    ch.name::text AS church_name,
    ch.treasurer_phone::text AS treasurer_phone,
    COALESCE(cf.gross, 0) AS gross_collected,
    COALESCE(cm.gross, 0) AS committed_giving,
    COALESCE(ifw.gross, 0) AS in_flight_withdrawals,
    GREATEST(0, COALESCE(cf.gross, 0) - COALESCE(cm.gross, 0) - COALESCE(ifw.gross, 0)) AS withdrawable
  FROM public.churches ch
  LEFT JOIN confirmed cf ON cf.church_id = ch.id::text
  LEFT JOIN committed cm ON cm.church_id = ch.id::text
  LEFT JOIN inflight ifw ON ifw.church_id = ch.id::text
  WHERE ch.treasurer_phone IS NOT NULL
    AND COALESCE(cf.gross, 0) > 0
$$;

REVOKE EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() FROM anon;
REVOKE EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() FROM PUBLIC;

-- ── Withdrawable balances (admin dashboard) ───────────────────────────────────
-- Role-gated wrapper around the server-side core: SECURITY DEFINER would
-- otherwise bypass the table RLS, so we gate on the caller's role explicitly.
CREATE OR REPLACE FUNCTION public.get_church_withdrawable_balances()
RETURNS TABLE (
  church_id TEXT,
  church_name TEXT,
  treasurer_phone TEXT,
  gross_collected NUMERIC,
  committed_giving NUMERIC,
  in_flight_withdrawals NUMERIC,
  withdrawable NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop')
  ) THEN
    RETURN;  -- empty result set
  END IF;

  RETURN QUERY SELECT * FROM public._church_withdrawable_balances_svc();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_church_withdrawable_balances() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_church_withdrawable_balances() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_church_withdrawable_balances() TO authenticated;

-- ── Auto-payout enqueue (service-role only) ───────────────────────────────────
-- For every church whose server-side withdrawable balance >= threshold, create a
-- church_withdrawals ledger row + a payout_tasks('church_payout') task in one
-- transaction. The partial unique index guarantees only one in-flight withdrawal
-- per church, so concurrent cron/webhook runs can never double-enqueue. Races are
-- caught per-church and skipped.
CREATE OR REPLACE FUNCTION public.enqueue_church_auto_payouts(p_min_kwacha NUMERIC DEFAULT 100)
RETURNS TABLE (
  church_id TEXT,
  church_name TEXT,
  withdrawal_id UUID,
  task_id UUID,
  gross_amount NUMERIC,
  recipient_phone TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_min NUMERIC := GREATEST(COALESCE(p_min_kwacha, 100), 0);
  rec RECORD;
  v_withdrawal_id UUID;
  v_task_id UUID;
BEGIN
  FOR rec IN
    SELECT * FROM public._church_withdrawable_balances_svc()
    WHERE withdrawable >= v_min
  LOOP
    BEGIN
      INSERT INTO public.church_withdrawals
        (church_id, church_name, gross_amount, recipient_phone, status)
      VALUES (rec.church_id, rec.church_name, rec.withdrawable, rec.treasurer_phone, 'pending')
      RETURNING id INTO v_withdrawal_id;

      INSERT INTO public.payout_tasks
        (source, source_ref, payment_ref, user_id, recipient_phone, gross_amount, status)
      VALUES ('church_payout', v_withdrawal_id::text, NULL, NULL, rec.treasurer_phone, rec.withdrawable, 'pending')
      RETURNING id INTO v_task_id;

      church_id := rec.church_id;
      church_name := rec.church_name;
      withdrawal_id := v_withdrawal_id;
      task_id := v_task_id;
      gross_amount := rec.withdrawable;
      recipient_phone := rec.treasurer_phone;
      RETURN NEXT;
    EXCEPTION WHEN unique_violation THEN
      -- Another enqueue already created this church's in-flight withdrawal. Skip.
    END;
  END LOOP;
  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM PUBLIC;

-- ── Withdrawal history (admin dashboard) ──────────────────────────────────────
-- Role-gated like the balances RPC above.
CREATE OR REPLACE FUNCTION public.get_church_withdrawals(p_limit INTEGER DEFAULT 100)
RETURNS SETOF public.church_withdrawals
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin','employee','coa_employee','treasurer','pastor','bishop')
  ) THEN
    RETURN;  -- empty result set
  END IF;

  RETURN QUERY
  SELECT * FROM public.church_withdrawals
  ORDER BY created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_church_withdrawals(INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_church_withdrawals(INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_church_withdrawals(INTEGER) TO authenticated;

-- ── Config key: auto-payout minimum threshold (kwacha) ────────────────────────
INSERT INTO public.platform_settings (key, value, updated_at)
VALUES ('church_payout_min_kwacha', '100', now())
ON CONFLICT (key) DO NOTHING;
