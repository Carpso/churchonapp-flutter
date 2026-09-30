-- 20261235_church_payout_dedupe.sql
-- Bug: after a disburse() failure, markTaskFailed() flips the church's
-- church_withdrawals row to 'failed', which releases the partial-unique
-- in-flight slot. The payout task itself stays 'pending' (retry backoff),
-- so the next lps-settle cron run enqueued ANOTHER withdrawal+task for the
-- SAME balance — 4 pending church_payout tasks for one K79 balance were live
-- on 2026-09-30 (up to ~4x double-pay once disburse was fixed).
--
-- Fix 1 (data): cancel every duplicate pending church_payout task, keeping
--   the best single task per church (unattempted first, then largest gross).
--   Their withdrawals are cancelled too, so the balance math re-includes the
--   money only once (the kept task still owns it).
-- Fix 2 (code): enqueue_church_auto_payouts skips a church that already has
--   a pending/processing church_payout TASK — a task in retry backoff still
--   owns the balance even when its withdrawal row says 'failed'. A fresh
--   enqueue is only allowed once that task reaches a terminal state.

-- ── 1. Cancel duplicate pending church_payout tasks (keep one per church) ──
WITH ranked AS (
  SELECT t.id,
         ROW_NUMBER() OVER (
           PARTITION BY w.church_id
           ORDER BY (t.attempt_count = 0) DESC,
                    t.gross_amount DESC,
                    t.created_at DESC
         ) AS rn
  FROM public.payout_tasks t
  JOIN public.church_withdrawals w ON w.id::text = t.source_ref
  WHERE t.source = 'church_payout'
    AND t.status = 'pending'
)
UPDATE public.payout_tasks t
SET status = 'cancelled',
    last_error = 'superseded_duplicate',
    updated_at = now()
FROM ranked r
WHERE t.id = r.id
  AND r.rn > 1;

-- ── 2. Cancel the withdrawals that belonged to those cancelled tasks ────────
UPDATE public.church_withdrawals w
SET status = 'cancelled',
    updated_at = now()
WHERE w.status IN ('pending', 'processing', 'failed')
  AND EXISTS (
    SELECT 1 FROM public.payout_tasks t
    WHERE t.source = 'church_payout'
      AND t.status = 'cancelled'
      AND t.last_error = 'superseded_duplicate'
      AND t.source_ref::uuid = w.id
  );

-- ── 3. Guard the enqueue RPC: one live church_payout task per church ───────
CREATE OR REPLACE FUNCTION public.enqueue_church_auto_payouts(p_min_kwacha numeric DEFAULT 100)
RETURNS TABLE(church_id text, church_name text, withdrawal_id uuid, task_id uuid, gross_amount numeric, recipient_phone text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_min NUMERIC := GREATEST(COALESCE(p_min_kwacha, 100), 0); rec RECORD; v_withdrawal_id UUID; v_task_id UUID;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Not authorized'; -- service role only (cron / webhook)
    END IF;
    FOR rec IN SELECT * FROM public._church_withdrawable_balances_svc() WHERE withdrawable >= v_min LOOP
        -- A pending/processing church_payout task already owns this balance,
        -- even if its withdrawal row was flipped to 'failed' after a retryable
        -- disburse error (backoff). Enqueueing again would double/triple pay.
        IF EXISTS (
            SELECT 1
            FROM public.payout_tasks t
            JOIN public.church_withdrawals w ON w.id::text = t.source_ref
            WHERE t.source = 'church_payout'
              AND t.status IN ('pending', 'processing')
              AND w.church_id = rec.church_id
        ) THEN
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO public.church_withdrawals (church_id, church_name, gross_amount, recipient_phone, status)
            VALUES (rec.church_id, rec.church_name, rec.withdrawable, rec.treasurer_phone, 'pending')
            RETURNING id INTO v_withdrawal_id;
            INSERT INTO public.payout_tasks (source, source_ref, payment_ref, user_id, recipient_phone, gross_amount, status)
            VALUES ('church_payout', v_withdrawal_id::text, NULL, NULL, rec.treasurer_phone, rec.withdrawable, 'pending')
            RETURNING id INTO v_task_id;
            church_id := rec.church_id; church_name := rec.church_name; withdrawal_id := v_withdrawal_id;
            task_id := v_task_id; gross_amount := rec.withdrawable; recipient_phone := rec.treasurer_phone;
            RETURN NEXT;
        EXCEPTION WHEN unique_violation THEN
            NULL; -- another enqueue already created this church's in-flight withdrawal
        END;
    END LOOP;
    RETURN;
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM anon;
REVOKE ALL ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) TO service_role;
