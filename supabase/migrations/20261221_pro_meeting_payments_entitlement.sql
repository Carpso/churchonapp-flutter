ALTER TABLE public.meeting_subscriptions ADD COLUMN IF NOT EXISTS status text DEFAULT 'active';
ALTER TABLE public.meeting_subscriptions ADD COLUMN IF NOT EXISTS plan text;
ALTER TABLE public.meeting_subscriptions ADD COLUMN IF NOT EXISTS amount_kwacha numeric;
ALTER TABLE public.meeting_subscriptions ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE public.meeting_subscriptions ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
-- PRO BUSINESS MEETING ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â PAYMENTS + ENTITLEMENT + COA ADMIN (2026-09-22)
--
-- SECURITY PROBLEM BEING CLOSED
--   Previously "activation" was a CLIENT-SIDE `meeting_subscriptions.insert`
--   with a client-declared amount/plan: no server verification, no entitlement
--   gate and no COA cut. Any client could grant itself Pro for free.
--
-- FIX (mirrors the established money patterns: 20260910 anchoring,
-- 20260890 auto-payout, PAYMENTS.md "DO NOT REGRESS"):
--   * The CLIENT NEVER decides price, plan or entitlement. The price is
--     re-derived server-side from `platform_settings` (remote-configurable).
--   * request_meeting_subscription() pre-creates the pending `coa_payments`
--     anchor and returns its reference + the server price.
--   * activate_meeting_subscription() flips to `active` ONLY when a CONFIRMED
--     `coa_payments` row (approved/completed/confirmed/settled) exists with
--     amount >= the server price. Idempotent.
--   * A trigger on `coa_payments` confirm/settle auto-activates the
--     subscription (mirrors `coa_payments_sync_church_fee`), so the client
--     never has to call activate at all.
--   * meeting_entitlement() is the SINGLE UI gate; it FAILS CLOSED.
--   * Writes to meeting_subscriptions are RPC/service-role only (no client
--     INSERT/UPDATE/DELETE policy) + one ACTIVE subscription per tenant.
-- ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 1. Extend meeting_subscriptions ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
ALTER TABLE public.meeting_subscriptions
  ADD COLUMN IF NOT EXISTS plan              text,
  ADD COLUMN IF NOT EXISTS amount_kwacha     numeric(12,2),
  ADD COLUMN IF NOT EXISTS started_at        timestamptz,
  ADD COLUMN IF NOT EXISTS coa_payment_id    uuid,
  ADD COLUMN IF NOT EXISTS auto_renew        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cancelled_at      timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at       timestamptz,
  ADD COLUMN IF NOT EXISTS refund_ref        text,
  ADD COLUMN IF NOT EXISTS coa_cut_kwacha    numeric(12,2),
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();

-- Backfill the new canonical columns from the legacy ones.
UPDATE public.meeting_subscriptions
   SET plan = COALESCE(plan, plan_type, 'monthly'),
       amount_kwacha = COALESCE(amount_kwacha, 0),
       started_at = COALESCE(started_at, CASE WHEN status = 'active' THEN created_at END)
 WHERE plan IS NULL OR amount_kwacha IS NULL OR started_at IS NULL;

-- Normalise any legacy status value before adding the CHECK.
UPDATE public.meeting_subscriptions
   SET status = 'expired'
 WHERE status IS NULL
    OR status NOT IN ('pending','active','expired','cancelled','refunded');

ALTER TABLE public.meeting_subscriptions
  DROP CONSTRAINT IF EXISTS meeting_subscriptions_status_check;
ALTER TABLE public.meeting_subscriptions
  ADD CONSTRAINT meeting_subscriptions_status_check
  CHECK (status IN ('pending','active','expired','cancelled','refunded')) NOT VALID;

-- Keep only the newest active row per tenant before adding the unique index
-- (legacy client inserts could have created duplicates).
UPDATE public.meeting_subscriptions s
   SET status = 'expired', updated_at = now()
 WHERE s.status = 'active'
   AND s.id <> (
     SELECT o.id FROM public.meeting_subscriptions o
      WHERE (o.metadata->>'tenant_id') = s.tenant_id AND o.status = 'active'
      ORDER BY o.created_at DESC NULLS LAST, o.id DESC
      LIMIT 1
   );

-- Exactly ONE active subscription per tenant (server-enforced).
CREATE UNIQUE INDEX IF NOT EXISTS meeting_subscriptions_one_active_tenant
  ON public.meeting_subscriptions (tenant_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS meeting_subscriptions_status_idx
  ON public.meeting_subscriptions (status, created_at);
CREATE INDEX IF NOT EXISTS meeting_subscriptions_payment_idx
  ON public.meeting_subscriptions (payment_ref);

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 2. RLS: tenant members read own, staff read all, writes via RPC only ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
ALTER TABLE public.meeting_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "meeting_subscriptions_select_own" ON public.meeting_subscriptions;
DROP POLICY IF EXISTS "meeting_subscriptions_insert_own" ON public.meeting_subscriptions;
DROP POLICY IF EXISTS "meeting_subscriptions_select" ON public.meeting_subscriptions;

CREATE POLICY "meeting_subscriptions_select" ON public.meeting_subscriptions
  FOR SELECT TO authenticated
  USING (
    auth.uid() = user_id
    OR tenant_id::text = public.get_my_tenant_id()
    OR public.is_platform_staff()
  );

-- No client INSERT/UPDATE/DELETE policies: the row is written only by the
-- SECURITY DEFINER RPCs and the coa_payments trigger (service-role equivalent).

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 3. Remote-configurable pricing / plan limits ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
INSERT INTO public.platform_settings (key, value, updated_at) VALUES
  ('meeting_pro_monthly_kwacha',        '150',  now()),
  ('meeting_pro_yearly_kwacha',         '1500', now()),
  ('coa_meeting_cut_percent',           '0.30', now()),
  ('meeting_max_participants_monthly',  '10',   now()),
  ('meeting_max_participants_yearly',   '25',   now()),
  ('meeting_can_record',                'true', now()),
  ('meeting_can_recur',                 'true', now()),
  ('meeting_free_max_participants',     '5',    now())
ON CONFLICT (key) DO NOTHING;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 4. Plan helpers (server-side price derivation ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never trust the client) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
CREATE OR REPLACE FUNCTION public.meeting_plan_days(p_plan text)
RETURNS int
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN lower(COALESCE(p_plan,'monthly')) = 'yearly' THEN 365 ELSE 30 END;
$$;

CREATE OR REPLACE FUNCTION public.meeting_plan_price(p_plan text)
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_plan text := lower(COALESCE(p_plan, 'monthly'));
  v_val  numeric;
BEGIN
  IF v_plan NOT IN ('monthly','yearly') THEN
    RAISE EXCEPTION 'Invalid meeting plan: %', p_plan;
  END IF;

  SELECT value::numeric INTO v_val FROM public.platform_settings
   WHERE key = CASE WHEN v_plan = 'yearly'
                    THEN 'meeting_pro_yearly_kwacha'
                    ELSE 'meeting_pro_monthly_kwacha' END
   LIMIT 1;

  -- Legacy key fallback (meeting_monthly_price / meeting_yearly_price).
  IF v_val IS NULL THEN
    SELECT value::numeric INTO v_val FROM public.platform_settings
     WHERE key = CASE WHEN v_plan = 'yearly'
                      THEN 'meeting_yearly_price'
                      ELSE 'meeting_monthly_price' END
     LIMIT 1;
  END IF;

  RETURN COALESCE(v_val, CASE WHEN v_plan = 'yearly' THEN 1500 ELSE 150 END);
END;
$$;

CREATE OR REPLACE FUNCTION public.meeting_plan_max_participants(p_plan text)
RETURNS int
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_plan text := lower(COALESCE(p_plan, 'monthly'));
  v_val  int;
BEGIN
  SELECT value::int INTO v_val FROM public.platform_settings
   WHERE key = CASE WHEN v_plan = 'yearly'
                    THEN 'meeting_max_participants_yearly'
                    ELSE 'meeting_max_participants_monthly' END
   LIMIT 1;
  RETURN COALESCE(v_val, CASE WHEN v_plan = 'yearly' THEN 25 ELSE 10 END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.meeting_plan_days(text)             FROM anon;
REVOKE EXECUTE ON FUNCTION public.meeting_plan_price(text)            FROM anon;
REVOKE EXECUTE ON FUNCTION public.meeting_plan_max_participants(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.meeting_plan_price(text)            FROM public;
REVOKE EXECUTE ON FUNCTION public.meeting_plan_max_participants(text) FROM public;
GRANT  EXECUTE ON FUNCTION public.meeting_plan_price(text)            TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.meeting_plan_max_participants(text) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 5. Expire stale active subscriptions (called by the read paths) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
CREATE OR REPLACE FUNCTION public.expire_meeting_subscriptions(p_tenant_id uuid DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_n int := 0;
BEGIN
  UPDATE public.meeting_subscriptions
     SET status = 'expired', updated_at = now()
   WHERE status = 'active'
     AND expires_at IS NOT NULL
     AND expires_at <= now()
     AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id);

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_meeting_subscriptions(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.expire_meeting_subscriptions(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.expire_meeting_subscriptions(uuid) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 6. request_meeting_subscription ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
-- Re-derives the price server-side, pre-creates the pending `coa_payments`
-- anchor (PAYMENTS.md rule 7) and returns {payment_ref, amount_kwacha, plan}.
-- The client NEVER supplies an amount or a price.
CREATE OR REPLACE FUNCTION public.request_meeting_subscription(
  p_tenant_id uuid,
  p_plan      text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_plan     text := lower(COALESCE(p_plan, 'monthly'));
  v_amount   numeric;
  v_ref      text;
  v_sub_id   uuid;
  v_pay_id   uuid;
  v_is_member boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant required';
  END IF;
  IF v_plan NOT IN ('monthly','yearly') THEN
    RAISE EXCEPTION 'Invalid meeting plan: %', p_plan;
  END IF;

  -- Authorization: a member of the tenant, or platform staff.
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_uid AND p.tenant_id = p_tenant_id::text
  ) INTO v_is_member;
  IF NOT (v_is_member OR public.is_platform_staff()) THEN
    RAISE EXCEPTION 'not allowed to subscribe for this tenant';
  END IF;

  v_amount := public.meeting_plan_price(v_plan);

  -- Reuse an existing unpaid pending anchor for the same tenant+plan.
  SELECT id, coa_payment_id INTO v_sub_id, v_pay_id
    FROM public.meeting_subscriptions
   WHERE tenant_id = p_tenant_id
     AND status = 'pending'
     AND COALESCE(plan, plan_type, 'monthly') = v_plan
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_pay_id IS NOT NULL THEN
    SELECT payment_ref INTO v_ref
      FROM public.coa_payments
     WHERE id = v_pay_id AND status = 'pending';
  END IF;

  IF v_ref IS NULL THEN
    v_ref := 'MTG-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

    -- Pre-create the server-side anchor BEFORE any provider round-trip.
    INSERT INTO public.coa_payments
      (user_id, service_type, amount, payment_ref, status, category, metadata)
    VALUES
      (v_uid, 'meeting_subscription', v_amount, v_ref, 'pending', 'meeting_subscription',
       jsonb_build_object(
         'tenant_id', p_tenant_id::text,
         'plan', v_plan,
         'user_id', v_uid,
         'purpose', 'pro_meeting'
       ))
    RETURNING id INTO v_pay_id;

    INSERT INTO public.meeting_subscriptions
      (user_id, tenant_id, plan, plan_type, amount_kwacha, amount_kwacha,
       payment_ref, coa_payment_id, status)
    VALUES
      (v_uid, p_tenant_id, v_plan, v_plan, v_amount, v_amount,
       v_ref, v_pay_id, 'pending')
    RETURNING id INTO v_sub_id;
  ELSE
    -- Keep the anchor at the CURRENT server price (never a stale client value).
    UPDATE public.coa_payments
       SET amount = v_amount,
           metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('plan', v_plan),
           updated_at = now()
     WHERE payment_ref = v_ref;

    UPDATE public.meeting_subscriptions
       SET amount_kwacha = v_amount,
           amount_kwacha = v_amount,
           updated_at = now()
     WHERE id = v_sub_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'payment_ref', v_ref,
    'amount_kwacha', v_amount,
    'plan', v_plan,
    'subscription_id', v_sub_id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_meeting_subscription(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.request_meeting_subscription(uuid, text) FROM public;
GRANT  EXECUTE ON FUNCTION public.request_meeting_subscription(uuid, text) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 7. activate_meeting_subscription ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
-- Flips to `active` ONLY against a CONFIRMED coa_payments row with
-- amount >= the server price. Idempotent.
CREATE OR REPLACE FUNCTION public.activate_meeting_subscription(p_payment_ref text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_pay    record;
  v_sub    record;
  v_plan   text;
  v_amount numeric;
  v_days   int;
  v_cut    numeric;
BEGIN
  IF p_payment_ref IS NULL OR p_payment_ref = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing payment reference');
  END IF;

  SELECT * INTO v_pay FROM public.coa_payments
   WHERE payment_ref = p_payment_ref
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_pay.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'payment not found');
  END IF;
  IF v_pay.status NOT IN ('approved','completed','confirmed','settled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'payment not confirmed');
  END IF;

  SELECT * INTO v_sub FROM public.meeting_subscriptions
   WHERE coa_payment_id = v_pay.id OR payment_ref = p_payment_ref
   ORDER BY created_at DESC
   LIMIT 1;

  -- Robustness: if no subscription row was pre-created (e.g. a legacy client
  -- that paid with a fresh reference), materialise one from the CONFIRMED
  -- payment's server facts only ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never from a client-declared amount/plan.
  IF v_sub.id IS NULL THEN
    DECLARE
      v_tid  uuid;
      v_plan0 text;
    BEGIN
      v_tid := NULLIF(v_pay.metadata->>'tenant_id', '')::uuid;
      IF v_tid IS NULL THEN
        SELECT p.tenant_id::uuid INTO v_tid
          FROM public.profiles p WHERE p.id = v_pay.user_id;
      END IF;
      IF v_tid IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'tenant not resolvable');
      END IF;

      v_plan0 := lower(COALESCE(v_pay.metadata->>'plan', 'monthly'));
      IF v_plan0 NOT IN ('monthly','yearly') THEN
        v_plan0 := 'monthly';
      END IF;

      INSERT INTO public.meeting_subscriptions
        (user_id, tenant_id, plan, plan_type, amount_kwacha, amount_kwacha,
         payment_ref, coa_payment_id, status)
      VALUES
        (v_pay.user_id, v_tid, v_plan0, v_plan0, v_pay.amount, v_pay.amount,
         p_payment_ref, v_pay.id, 'pending')
      RETURNING * INTO v_sub;
    END;
  END IF;

  IF v_sub.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'subscription not found');
  END IF;

  IF NOT (v_sub.user_id = v_uid
          OR public.is_tenant_owner(v_sub.tenant_id::text)
          OR public.is_platform_staff()) THEN
    RAISE EXCEPTION 'not allowed';
  END IF;

  -- Idempotent: already active and unexpired.
  IF v_sub.status = 'active' AND (v_sub.expires_at IS NULL OR v_sub.expires_at > now()) THEN
    RETURN jsonb_build_object('success', true, 'already_active', true,
                              'plan', COALESCE(v_sub.plan, v_sub.plan_type),
                              'expires_at', v_sub.expires_at);
  END IF;

  v_plan := COALESCE(v_sub.plan, v_sub.plan_type, 'monthly');
  v_amount := public.meeting_plan_price(v_plan);
  v_days := public.meeting_plan_days(v_plan);

  IF v_pay.amount < v_amount - 0.01 THEN
    RETURN jsonb_build_object('success', false, 'error', 'amount below plan price');
  END IF;

  v_cut := round(v_pay.amount * COALESCE((
            SELECT value::numeric FROM public.platform_settings
             WHERE key = 'coa_meeting_cut_percent' LIMIT 1), 0.30), 2);

  -- Expire any other active subscription for this tenant (unique-index guard).
  UPDATE public.meeting_subscriptions
     SET status = 'expired', updated_at = now()
   WHERE tenant_id = v_sub.tenant_id AND status = 'active' AND id <> v_sub.id;

  UPDATE public.meeting_subscriptions
     SET status = 'active',
         plan = v_plan,
         amount_kwacha = GREATEST(COALESCE(amount_kwacha, 0), v_pay.amount),
         coa_payment_id = v_pay.id,
         started_at = now(),
         expires_at = now() + make_interval(days => v_days),
         coa_cut_kwacha = v_cut,
         updated_at = now()
   WHERE id = v_sub.id;

  RETURN jsonb_build_object(
    'success', true,
    'plan', v_plan,
    'expires_at', now() + make_interval(days => v_days),
    'coa_cut_kwacha', v_cut
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.activate_meeting_subscription(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.activate_meeting_subscription(text) FROM public;
GRANT  EXECUTE ON FUNCTION public.activate_meeting_subscription(text) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 8. Auto-activate from a confirmed payment (client never has to call it) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
CREATE OR REPLACE FUNCTION public.trg_coa_payment_sync_meeting()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sub  record;
  v_days int;
  v_cut  numeric;
BEGIN
  IF NEW.status NOT IN ('approved','completed','confirmed','settled') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NOT (NEW.service_type = 'meeting_subscription'
          OR NEW.category = 'meeting_subscription'
          OR (NEW.metadata ? 'meeting_subscription_id')) THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT * INTO v_sub FROM public.meeting_subscriptions
     WHERE (coa_payment_id = NEW.id OR payment_ref = NEW.payment_ref)
       AND status IN ('pending','expired','cancelled')
     ORDER BY created_at DESC
     LIMIT 1;
    IF v_sub.id IS NULL THEN
      RETURN NEW;
    END IF;

    v_days := public.meeting_plan_days(COALESCE(v_sub.plan, v_sub.plan_type, 'monthly'));
    v_cut := round(NEW.amount * COALESCE((
              SELECT value::numeric FROM public.platform_settings
               WHERE key = 'coa_meeting_cut_percent' LIMIT 1), 0.30), 2);

    UPDATE public.meeting_subscriptions
       SET status = 'expired', updated_at = now()
     WHERE tenant_id = v_sub.tenant_id AND status = 'active' AND id <> v_sub.id;

    UPDATE public.meeting_subscriptions
       SET status = 'active',
           plan = COALESCE(plan, plan_type, 'monthly'),
           amount_kwacha = GREATEST(COALESCE(amount_kwacha, 0), NEW.amount),
           coa_payment_id = NEW.id,
           started_at = now(),
           expires_at = now() + make_interval(days => v_days),
           coa_cut_kwacha = v_cut,
           updated_at = now()
     WHERE id = v_sub.id;
  EXCEPTION WHEN OTHERS THEN
    -- Never let entitlement bookkeeping break a payment write.
    NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS coa_payments_sync_meeting ON public.coa_payments;
CREATE TRIGGER coa_payments_sync_meeting
  AFTER INSERT OR UPDATE OF status ON public.coa_payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_coa_payment_sync_meeting();

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 9. meeting_entitlement ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the SINGLE UI gate (fails closed) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
-- Returns a SUPERSET of keys so both the newer client contract
-- (is_pro / can_record / can_recur) and the legacy RPC contract
-- (pro / recording / recurring) keep working. Never trusts a client plan.
CREATE OR REPLACE FUNCTION public.meeting_entitlement(p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sub record;
  v_free_max int;
  v_plan text;
  v_is_pro boolean := false;
  v_max int;
  v_rec boolean := false;
  v_recur boolean := false;
  v_expires timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'is_pro', false, 'pro', false, 'status', 'none',
      'plan', NULL, 'expires_at', NULL, 'max_participants', 5,
      'can_record', false, 'recording', false,
      'can_recur', false, 'recurring', false, 'reason', 'unauthenticated');
  END IF;

  PERFORM public.expire_meeting_subscriptions(p_tenant_id);

  SELECT * INTO v_sub FROM public.meeting_subscriptions
   WHERE status = 'active'
     AND (expires_at IS NULL OR expires_at > now())
     AND (
       user_id = auth.uid()
       OR (p_tenant_id IS NOT NULL AND tenant_id = p_tenant_id)
     )
   ORDER BY expires_at DESC NULLS LAST, started_at DESC NULLS LAST
   LIMIT 1;

  IF v_sub.id IS NULL THEN
    v_free_max := COALESCE((SELECT value::int FROM public.platform_settings
                             WHERE key = 'meeting_free_max_participants' LIMIT 1), 5);
    RETURN jsonb_build_object(
      'is_pro', false, 'pro', false, 'status', 'none',
      'plan', NULL, 'expires_at', NULL, 'max_participants', v_free_max,
      'can_record', false, 'recording', false,
      'can_recur', false, 'recurring', false);
  END IF;

  v_is_pro  := true;
  v_plan    := COALESCE(v_sub.plan, v_sub.plan_type, 'monthly');
  v_expires := v_sub.expires_at;
  v_max     := public.meeting_plan_max_participants(v_plan);
  v_rec     := COALESCE((SELECT value::boolean FROM public.platform_settings
                          WHERE key = 'meeting_can_record' LIMIT 1), true);
  v_recur   := COALESCE((SELECT value::boolean FROM public.platform_settings
                          WHERE key = 'meeting_can_recur' LIMIT 1), true);

  RETURN jsonb_build_object(
    'is_pro', v_is_pro, 'pro', v_is_pro,
    'plan', v_plan, 'expires_at', v_expires,
    'max_participants', v_max,
    'can_record', v_rec, 'recording', v_rec,
    'can_recur', v_recur, 'recurring', v_recur,
    'status', 'active'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.meeting_entitlement(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.meeting_entitlement(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.meeting_entitlement(uuid) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 10. cancel / refund / force-expire ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
CREATE OR REPLACE FUNCTION public.cancel_meeting_subscription(p_subscription_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_sub FROM public.meeting_subscriptions WHERE id = p_subscription_id;
  IF v_sub.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'subscription not found');
  END IF;

  IF NOT (v_sub.user_id = v_uid
          OR public.is_tenant_owner(v_sub.tenant_id::text)
          OR public.is_platform_staff()) THEN
    RAISE EXCEPTION 'not allowed';
  END IF;

  UPDATE public.meeting_subscriptions
     SET status = 'cancelled',
         cancelled_at = now(),
         auto_renew = false,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_meeting_subscription(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.cancel_meeting_subscription(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.cancel_meeting_subscription(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.refund_meeting_subscription(
  p_subscription_id uuid,
  p_reason          text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sub record;
BEGIN
  IF NOT public.is_platform_staff() THEN
    RAISE EXCEPTION 'staff only';
  END IF;

  SELECT * INTO v_sub FROM public.meeting_subscriptions WHERE id = p_subscription_id;
  IF v_sub.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'subscription not found');
  END IF;

  UPDATE public.meeting_subscriptions
     SET status = 'refunded',
         refunded_at = now(),
         refund_ref = COALESCE(NULLIF(btrim(p_reason), ''), 'staff_refund'),
         cancelled_at = COALESCE(cancelled_at, now()),
         auto_renew = false,
         updated_at = now()
   WHERE id = p_subscription_id;

  -- Record the refund against the confirmed anchor (never a new row).
  IF v_sub.coa_payment_id IS NOT NULL THEN
    UPDATE public.coa_payments
       SET status = 'refunded', updated_at = now()
     WHERE id = v_sub.coa_payment_id
       AND status IN ('approved','completed','confirmed','settled');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.refund_meeting_subscription(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.refund_meeting_subscription(uuid, text) FROM public;
GRANT  EXECUTE ON FUNCTION public.refund_meeting_subscription(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.force_expire_meeting_subscription(p_subscription_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_staff() THEN
    RAISE EXCEPTION 'staff only';
  END IF;

  UPDATE public.meeting_subscriptions
     SET status = 'expired',
         cancelled_at = COALESCE(cancelled_at, now()),
         auto_renew = false,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.force_expire_meeting_subscription(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.force_expire_meeting_subscription(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.force_expire_meeting_subscription(uuid) TO authenticated, service_role;

-- ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ 11. COA admin report (revenue totals + rows, real data only) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
CREATE OR REPLACE FUNCTION public.get_meeting_admin_report(p_days int DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_from    timestamptz := now() - make_interval(days => GREATEST(COALESCE(p_days, 30), 1));
  v_rows    jsonb;
  v_summary jsonb;
BEGIN
  IF NOT public.is_platform_staff() THEN
    RAISE EXCEPTION 'staff only';
  END IF;

  PERFORM public.expire_meeting_subscriptions(NULL);

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT s.id, s.tenant_id, t.name AS tenant_name,
           COALESCE(s.plan, s.plan_type, 'monthly') AS plan,
           s.status,
           COALESCE(s.amount_kwacha, s.amount_kwacha, 0) AS amount_kwacha,
           s.started_at, s.expires_at, s.payment_ref, s.coa_payment_id,
           s.coa_cut_kwacha, s.auto_renew, s.cancelled_at, s.refunded_at,
           s.refund_ref, s.created_at
      FROM public.meeting_subscriptions s
      LEFT JOIN public.tenants t ON t.id = s.tenant_id
  ) t;

  SELECT jsonb_build_object(
    'active_count', (
      SELECT COUNT(*) FROM public.meeting_subscriptions
       WHERE status = 'active' AND (expires_at IS NULL OR expires_at > now())
    ),
    'new_count', (
      SELECT COUNT(*) FROM public.meeting_subscriptions
       WHERE started_at IS NOT NULL AND started_at >= v_from
    ),
    'mrr', (
      SELECT COALESCE(SUM(
               CASE WHEN COALESCE(plan, plan_type) = 'yearly'
                    THEN COALESCE(amount_kwacha, 0) / 12.0
                    ELSE COALESCE(amount_kwacha, 0) END), 0)
        FROM public.meeting_subscriptions
       WHERE status = 'active' AND (expires_at IS NULL OR expires_at > now())
    ),
    'collected', (
      SELECT COALESCE(SUM(COALESCE(amount_kwacha, 0)), 0)
        FROM public.meeting_subscriptions
       WHERE started_at IS NOT NULL AND started_at >= v_from
         AND status IN ('active','expired','cancelled','refunded')
    ),
    'refunds', (
      SELECT COALESCE(SUM(COALESCE(amount_kwacha, 0)), 0)
        FROM public.meeting_subscriptions
       WHERE status = 'refunded' AND refunded_at IS NOT NULL AND refunded_at >= v_from
    ),
    'coa_cut', (
      SELECT COALESCE(SUM(coa_cut_kwacha), 0)
        FROM public.meeting_subscriptions
       WHERE started_at IS NOT NULL AND started_at >= v_from
    )
  ) INTO v_summary;

  RETURN jsonb_build_object(
    'summary', v_summary,
    'subscriptions', v_rows,
    'window_days', GREATEST(COALESCE(p_days, 30), 1)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_meeting_admin_report(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_meeting_admin_report(int) FROM public;
GRANT  EXECUTE ON FUNCTION public.get_meeting_admin_report(int) TO authenticated, service_role;
