-- Giving settlement fix: track payouts per transaction so member-driven
-- auto-settlement (finance_service.logTransaction -> lipila-payout) can be
-- verified server-side and can never be paid out twice.

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS payout_ref TEXT;

CREATE INDEX IF NOT EXISTS idx_transactions_reference ON public.transactions(reference);
