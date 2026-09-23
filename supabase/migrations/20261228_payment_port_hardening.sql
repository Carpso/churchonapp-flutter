-- ═══════════════════════════════════════════════════════════════════════════════
-- PAYMENT PORT HARDENING (chisomo/Kingdom Sponsor parity)
--
-- Completes the 20261227 reconciliation/dunning port with the double-sweep guard
-- and the pledge auto-charge columns the settlement cron relies on.
--
-- Invariants preserved (PAYMENTS.md §9):
--   * Ledgers are service-role write only; clients read their own rows.
--   * No client can set a sweep amount or a payout recipient.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Fee sweeps: one settlement per Lipila reference ───────────────────────────
-- The sweep row is inserted before calling Lipila, so a retry/cron overlap can
-- never create a second settlement of the same fee reference.
CREATE UNIQUE INDEX IF NOT EXISTS fee_sweeps_reference_uniq
  ON public.fee_sweeps (lipila_reference)
  WHERE lipila_reference IS NOT NULL;

-- Which payout task/withdrawal the fee came from (audit trail).
ALTER TABLE public.fee_sweeps
  ADD COLUMN IF NOT EXISTS payout_task_id UUID;

-- ── Pledge auto-charge support ────────────────────────────────────────────────
-- `due_pledges_for_charge` / `record_pledge_charge` live in 20261227; this index
-- keeps the due-scan cheap as pledges grow.
CREATE INDEX IF NOT EXISTS pledges_auto_charge_due_idx
  ON public.pledges (next_charge_at)
  WHERE status = 'active' AND auto_charge = true;

-- ── Config defaults (idempotent) ──────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, updated_at) VALUES
  ('payout_retry_backoff_minutes', '30', now()),
  ('platform_fee_sweep_min_kwacha', '50', now()),
  ('coa_settlement_phone', '', now())
ON CONFLICT (key) DO NOTHING;
