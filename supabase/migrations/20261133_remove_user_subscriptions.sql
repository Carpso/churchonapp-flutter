-- ============================================================================
-- 20261133_remove_user_subscriptions.sql
-- Members pay NOTHING to join and NOTHING as a subscription.
--
--   * User-level silver/gold "tiers" are dead: `user_has_feature_access` now
--     always grants (features must not vanish), `subscribe_user_to_tier`
--     refuses to charge, and the user tier price keys are removed.
--   * Members may only ever pay for: quiz store kits, and Church Coins.
--   * CHURCHES pay the onboarding fee AFTER the trial. The fee is recorded
--     automatically and approved automatically from a confirmed `coa_payments`
--     row — no manual COA click required (COA can still approve/revoke).
--   * Trials expire server-side (cron), not only in the client.
-- ============================================================================

-- ── 1. User subscriptions removed ───────────────────────────────────────────
-- Keep the function (the client calls it) but it no longer gates anything.
CREATE OR REPLACE FUNCTION public.user_has_feature_access(
  feature_key text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT true;
$$;

REVOKE EXECUTE ON FUNCTION public.user_has_feature_access(text) FROM anon;

DO $$
BEGIN
  -- Legacy 1-arg/2-arg variants, if they exist.
  EXECUTE 'CREATE OR REPLACE FUNCTION public.user_has_feature_access(p_user_id uuid, p_feature_key text)
           RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$ SELECT true; $fn$';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- No user tier may ever be charged again.
CREATE OR REPLACE FUNCTION public.subscribe_user_to_tier(
  p_tier        text,
  p_payment_ref text DEFAULT NULL,
  p_amount      numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Product decision: individual members never subscribe. The only paid
  -- member purchases are quiz store kits and Church Coins.
  RETURN jsonb_build_object(
    'subscribed', false,
    'reason', 'user_subscriptions_removed',
    'message', 'Members never pay a subscription. Member purchases are limited to quiz store kits and Church Coins.'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.subscribe_user_to_tier(text, text, numeric) FROM anon;

-- Drop the dead user-tier pricing keys (keep the tenant/plan keys).
DELETE FROM public.platform_settings
 WHERE key IN ('user_silver_monthly_price', 'user_gold_yearly_price',
               'user_silver_yearly_price', 'user_gold_monthly_price',
               'silver_monthly_fee', 'gold_yearly_fee');

-- ── 2. Church onboarding fee: auto-recorded + auto-approved ─────────────────
-- The confirmed ledger row is the ONLY source of truth. Amount is re-derived
-- server-side from platform_settings.
CREATE OR REPLACE FUNCTION public.sync_church_onboarding_fee(p_tenant_id text DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fee   numeric;
  v_row   record;
  v_paid  numeric;
  v_n     int := 0;
BEGIN
  SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
                    WHERE key = 'onboarding_fee' LIMIT 1), 0)
    INTO v_fee;

  FOR v_row IN
    SELECT id, tenant_id, name FROM public.churches
     WHERE COALESCE(onboarding_fee_paid, false) = false
       AND subscription_ends_at IS NOT NULL
       AND (p_tenant_id IS NULL OR tenant_id::text = p_tenant_id)
  LOOP
    SELECT COALESCE(SUM(amount), 0) INTO v_paid
      FROM public.coa_payments
     WHERE status IN ('approved', 'completed', 'confirmed', 'settled')
       AND metadata->>'tenant_id' = v_row.tenant_id::text
       AND amount >= v_fee;

    IF v_paid >= v_fee THEN
      UPDATE public.churches
         SET onboarding_fee_paid = true,
             onboarding_fee_paid_at = now(),
             onboarding_fee_ref = v_row.tenant_id::text,
             subscription_status = 'active'
       WHERE id = v_row.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_church_onboarding_fee(text) FROM anon;

-- Auto-run whenever a payment is confirmed/settled.
CREATE OR REPLACE FUNCTION public.trg_coa_payment_sync_fee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('approved', 'completed', 'confirmed', 'settled')
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    BEGIN
      PERFORM public.sync_church_onboarding_fee(NEW.metadata->>'tenant_id');
    EXCEPTION WHEN OTHERS THEN
      -- Never let fee bookkeeping break a payment write.
      NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS coa_payments_sync_church_fee ON public.coa_payments;
CREATE TRIGGER coa_payments_sync_church_fee
  AFTER INSERT OR UPDATE OF status ON public.coa_payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_coa_payment_sync_fee();

-- ── 3. Server-side trial expiry + COA alerting cron ─────────────────────────
CREATE OR REPLACE FUNCTION public.expire_church_trials()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n int := 0;
BEGIN
  UPDATE public.churches
     SET subscription_status = 'expired'
   WHERE subscription_ends_at IS NOT NULL
     AND subscription_ends_at < now()
     AND COALESCE(subscription_status, 'trial') NOT IN ('expired', 'cancelled', 'suspended');

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_church_trials() FROM anon;
REVOKE EXECUTE ON FUNCTION public.expire_church_trials() FROM authenticated;

-- Owner-tier reminders (7 days out by default) for the COA team.
CREATE OR REPLACE FUNCTION public.notify_trial_expiry(p_days int DEFAULT 7)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_owner record;
  v_n int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.get_tenancy_payment_reminders(p_days)
  LOOP
    FOR v_owner IN
      SELECT (o->>'user_id')::uuid AS uid
      FROM jsonb_array_elements(v_row.owners) o
    LOOP
      IF v_owner.uid IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, title, body, type, created_at)
        VALUES (
          v_owner.uid,
          'Church subscription due',
          v_row.church_name || ' has ' || v_row.days_left ||
            ' day(s) left on its trial. Please settle the subscription to keep all features on.',
          'subscription_due',
          now()
        );
        v_n := v_n + 1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notify_trial_expiry(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_trial_expiry(int) FROM authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule('trial-expiry-sweep');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'trial-expiry-sweep',
  '0 6 * * *',
  $$SELECT public.expire_church_trials(); SELECT public.notify_trial_expiry(7);$$
);
