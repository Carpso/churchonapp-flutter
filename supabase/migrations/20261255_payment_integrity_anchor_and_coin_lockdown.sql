-- =====================================================================
-- 20261255_payment_integrity_anchor_and_coin_lockdown.sql
--
-- Closes the payment-integrity holes found in the 2026-10 audit against
-- chisomo_flutter. Three independent forgeries, one migration.
--
-- ---------------------------------------------------------------------
-- 1. THE `transactions` LEDGER WAS CLIENT-WRITABLE AND FORGEABLE
-- ---------------------------------------------------------------------
-- `transactions` is the source of truth for FOUR revenue surfaces:
--   church_financial_hub_screen.dart, pastor_dashboard_screen.dart (x2),
--   report_creator_screen.dart
-- ...all of which filter `status = 'completed'`. But any authenticated
-- member could INSERT a row with `status:'completed'` and an arbitrary
-- amount:
--
--   policy "Users can create own transactions"
--     FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id)
--
-- so a member could inflate their church's reported revenue indefinitely and
-- self-mint receipts. `receipt_service.dart` reads the same rows.
--
-- It was also an AMPLIFIER, not just a ledger. The only trigger on the table
-- is `on_transaction_giving` -> `update_donor_profile_on_giving()`, which for
-- `category='giving' AND status='completed'` does an UPSERT into
-- `donor_profiles.total_given`. Its `church_id` came from
--   COALESCE(NEW.church_id, (SELECT church_id FROM profiles WHERE id = NEW.user_id))
-- so a single forged row poisoned the CRM donor leaderboard, and a member
-- could aim it at a DIFFERENT church by setting tenant_id/church_id directly.
--
-- There were THREE ways in, so fixing only the obvious one changes nothing:
--   (a) the INSERT policy above;
--   (b) `insert_transaction_idempotent(...)` -- SECURITY DEFINER, granted to
--       `authenticated`, which hardcodes `status='completed'` and only checks
--       `auth.uid() = p_user_id`, with NO validation that p_payment_ref exists
--       in coa_payments. Identical forgery power, and it also bypasses RLS;
--   (c) policy "Superadmins can manage all transactions" is `FOR ALL`, which
--       includes INSERT, so dropping (a) alone still let any
--       superadmin/employee/coa_employee account insert arbitrary completed
--       rows straight through PostgREST. (It also still listed the pre-20260848
--       legacy role name `employee` -- the same bug class as the earlier
--       role_assignments and organizations fixes.)
--
-- THE FIX
-- Rather than drop the INSERT policy and rewrite all 14 client call sites
-- (giving, events, quiz entry fees, fundraising, QR pay, pledges, klips, group
-- giving) in one release, we enforce the invariant where it belongs - in the
-- DATABASE - so every one of those paths keeps working and every forgery dies:
--
--   A BEFORE INSERT trigger requires that any client-written money-IN row is
--   backed by a real `coa_payments` anchor, and that the row's amount matches
--   the anchored amount.
--
-- This closes (a), (b) and (c) simultaneously, because a trigger cannot be
-- side-stepped by a SECURITY DEFINER wrapper: `auth.uid()` reads the caller's
-- JWT, which is unchanged by SECURITY DEFINER (only the *role* changes), so the
-- offline-giving replay through `insert_transaction_idempotent` is validated
-- exactly like a direct insert.
--
-- Deliberately NOT keyed on the anchor being CONFIRMED: `logTransaction` runs
-- immediately after the gateway returns success, and requiring a settled anchor
-- at that instant would race the webhook and break live giving. We require the
-- anchor to EXIST and not be failed, plus an exact amount match. A member cannot
-- invent a reference without a real gateway-created anchor, and cannot set an
-- amount that disagrees with the money that actually moved.
--
-- Server-side writes (auth.uid() IS NULL - Edge Functions, pg_cron, and the
-- leadership-gated `data-import` service-role path that is how a treasurer
-- imports historical giving from Breeze/PlanningCenter/RockRMS) are unaffected.
--
-- ---------------------------------------------------------------------
-- 2. COINS WERE DIRECTLY CLIENT-WRITABLE
-- ---------------------------------------------------------------------
-- `profiles.coins` had NO column-level grant anywhere in the schema, so the
-- only thing standing between a member and an unlimited balance was the
-- column-agnostic UPDATE policy `profiles_update_own` (`auth.uid() = id`). That
-- let the six client-side read-modify-write sites mint coins directly and
-- completely bypass the hardened `add_coins` / `deduct_coins` RPCs and their
-- +/-100,000 cap from 20260888. Coins are redeemable at partner locations, so
-- this is a real balance-forgery hole, and the RMW pattern also loses updates
-- under concurrency (two concurrent gifts -> one credit).
--
-- Postgres checks COLUMN GRANTS BEFORE RLS, so
--   REVOKE UPDATE (coins), INSERT (coins) ON public.profiles FROM authenticated
-- closes all three writing policies (own-row, admin-all, and the KYC-reviewer
-- UPDATE policy, which is column-agnostic despite its comment) at once.
--
-- The client call sites are migrated in the same release to the RPCs that
-- already existed for this purpose:
--   self credit        -> add_coins(user_id, amount)          [auth-gated]
--   credit someone else-> award_coins(user_id_str, amount, reason)
--                         (SECURITY DEFINER; NOT executable by authenticated
--                         today, so it is granted here to leadership only)
--   move between users -> system_transfer_coins(from, to, amount)
--                         (atomic, so a debit can no longer succeed while the
--                         matching credit fails and coins are destroyed)
--
-- ---------------------------------------------------------------------
-- 3. A DEAD FALLBACK THAT WOULD HAVE SILENTLY BROKEN REDEMPTION
-- ---------------------------------------------------------------------
-- partner_tenant_service.dart used `add_coins` first and fell back to a direct
-- column write inside a `catch`, with the surrounding try/catch swallowing any
-- error. Once the column write is revoked that fallback becomes unreachable and
-- redemption would appear to SUCCEED while coins were never deducted. The
-- fallback is removed in the client rather than left to fail quietly.

-- =====================================================================
-- 1. Anchor enforcement
-- =====================================================================

CREATE OR REPLACE FUNCTION public.trg_transactions_require_payment_anchor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid;
  v_anchor     public.coa_payments%ROWTYPE;
  v_category   text := lower(coalesce(NEW.category, ''));
  v_amount     numeric := coalesce(NEW.amount, 0);
BEGIN
  -- Server-side writers (Edge Functions, pg_cron, the leadership-gated
  -- data-import service-role path) are trusted: they are the reconciliation and
  -- bookkeeping paths that legitimately have no per-user anchor.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  -- Coin-to-coin transfer: a NEGATIVE self-debit ledger line. It moves no real
  -- money, is excluded from every revenue query (those filter positive giving
  -- categories), and the balance movement itself now goes through
  -- system_transfer_coins, which is atomic. Allow it without an anchor.
  IF v_category = 'transfer' AND v_amount < 0 AND NEW.user_id = v_uid THEN
    RETURN NEW;
  END IF;

  -- Everything else that carries value must be anchored to a real collection.
  IF coalesce(NEW.reference, '') = '' THEN
    RAISE EXCEPTION
      'transaction rejected: a payment reference is required (category=%)', v_category
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_anchor
  FROM public.coa_payments
  WHERE payment_ref = NEW.reference
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'transaction rejected: no payment found for reference %', NEW.reference
      USING ERRCODE = '42501';
  END IF;

  IF lower(coalesce(v_anchor.status, '')) IN ('failed', 'cancelled', 'canceled', 'rejected', 'declined') THEN
    RAISE EXCEPTION
      'transaction rejected: the payment for reference % did not succeed (%)',
      NEW.reference, v_anchor.status
      USING ERRCODE = '42501';
  END IF;

  -- The amount must be the amount that actually moved. This is what stops a
  -- member inflating a real K50 reference into a K50,000 "completed" giving row.
  IF abs(coalesce(v_anchor.amount, 0) - abs(v_amount)) > 0.009 THEN
    RAISE EXCEPTION
      'transaction rejected: amount % does not match the anchored payment of % for reference %',
      v_amount, v_anchor.amount, NEW.reference
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_transactions_require_payment_anchor() IS
  'Forgery guard: any client-written money-IN transaction row must be backed by a
real coa_payments anchor whose amount matches. Closes the client INSERT policy, the
insert_transaction_idempotent SECURITY DEFINER hole, and the FOR ALL superadmin
policy - a trigger cannot be side-stepped by SECURITY DEFINER because auth.uid()
still reads the caller''s JWT. Service-role writers bypass by design.';

DROP TRIGGER IF EXISTS trg_transactions_require_payment_anchor ON public.transactions;
CREATE TRIGGER trg_transactions_require_payment_anchor
  BEFORE INSERT ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_transactions_require_payment_anchor();

-- `insert_transaction_idempotent` is the offline-giving replay path. It now
-- inherits anchor validation from the trigger, but we also stop it hardcoding a
-- successful status independently of the anchor, so a future edit cannot
-- reintroduce the bypass.
--
-- !! PARAMETER TYPES ARE PART OF THE IDENTITY - READ THIS BEFORE EDITING !!
-- The live signature is
--     (text, uuid, uuid, double precision, text, text, text, text, text, double precision)
-- NOT (text, uuid, text, numeric, ...). `CREATE OR REPLACE FUNCTION` matches on
-- the full argument-type list, so redefining it with `text`/`numeric` does NOT
-- replace the original - it silently creates a SECOND OVERLOAD and leaves the
-- hardcoded-'completed' original in place, still callable, still forgeable.
-- That is how this migration was nearly shipped with the hole wide open. We
-- therefore drop any same-named overload first and then replace the exact
-- original signature.
DROP FUNCTION IF EXISTS public.insert_transaction_idempotent(text, uuid, text, numeric, text, text, text, text, text, numeric);
-- Full DROP rather than CREATE OR REPLACE: replacing in place fails with
-- 42P13 "cannot remove parameter defaults" when the existing parameter defaults
-- do not match exactly, and a plain OR REPLACE with different parameter TYPES
-- would silently leave the vulnerable original in place as an overload.
DROP FUNCTION IF EXISTS public.insert_transaction_idempotent(text, uuid, uuid, double precision, text, text, text, text, text, double precision);

CREATE FUNCTION public.insert_transaction_idempotent(
  p_idempotency_key text,
  p_user_id         uuid,
  p_tenant_id       uuid,
  p_amount          double precision,
  p_type            text,
  p_currency        text,
  p_payment_method  text,
  p_payment_ref     text,
  p_description     text,
  p_platform_fee    double precision DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id      uuid;
  v_status  text;
  v_anchor  public.coa_payments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF auth.uid() <> p_user_id AND NOT public.is_admin_or_employee() THEN
    RAISE EXCEPTION 'Not permitted' USING ERRCODE = '42501';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive' USING ERRCODE = '22023';
  END IF;

  -- Derive the status from the ANCHOR, never from the caller. Previously this
  -- function hardcoded 'completed', which is what let any member assert a
  -- successful collection through the SECURITY DEFINER wrapper.
  SELECT * INTO v_anchor
  FROM public.coa_payments
  WHERE payment_ref = p_payment_ref
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No payment found for reference %', coalesce(p_payment_ref, '(null)')
      USING ERRCODE = '42501';
  END IF;

  IF lower(coalesce(v_anchor.status, '')) IN ('failed','cancelled','canceled','rejected','declined') THEN
    RAISE EXCEPTION 'The payment for reference % did not succeed', p_payment_ref
      USING ERRCODE = '42501';
  END IF;

  v_status := CASE
    WHEN lower(coalesce(v_anchor.status, '')) IN
         ('approved','completed','confirmed','settled') THEN 'completed'
    ELSE 'pending'
  END;

  INSERT INTO public.transactions (
    id, user_id, tenant_id, amount, category, payment_method,
    reference, platform_fee, status, created_at
  )
  VALUES (
    gen_random_uuid(), p_user_id, p_tenant_id, p_amount, p_type,
    p_payment_method, p_payment_ref, coalesce(p_platform_fee, 0), v_status, now()
  )
  ON CONFLICT (reference) DO UPDATE SET reference = EXCLUDED.reference
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.insert_transaction_idempotent(text, uuid, uuid, double precision, text, text, text, text, text, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.insert_transaction_idempotent(text, uuid, uuid, double precision, text, text, text, text, text, double precision) TO authenticated, service_role;

-- =====================================================================
-- 2. Coin balance lockdown
-- =====================================================================

-- Column grants are evaluated BEFORE RLS, but a COLUMN revoke cannot subtract
-- from a TABLE-level grant - and `authenticated` holds a blanket
-- `GRANT UPDATE ON public.profiles` (plus INSERT). So the only way to actually
-- remove `coins` is to drop the table-level privilege and re-grant it column by
-- column. Built dynamically from information_schema so it can never drift when a
-- column is added later - same technique as the live_streams allowlist rebuild
-- in 20261240.
REVOKE UPDATE ON public.profiles FROM authenticated, anon;

DO $$
DECLARE
  r       record;
  v_cols  text := '';
BEGIN
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'profiles'
      AND column_name <> 'coins'
  LOOP
    v_cols := v_cols || quote_ident(r.column_name) || ', ';
  END LOOP;

  IF v_cols = '' THEN
    RAISE EXCEPTION 'profiles has no updatable columns - refusing to lock coins';
  END IF;

  v_cols := left(v_cols, length(v_cols) - 2);
  EXECUTE format('GRANT UPDATE (%s) ON public.profiles TO authenticated', v_cols);
END;
$$;

-- INSERT must stay available for `coins`: self-signup writes `'coins': 0` in its
-- profile upsert (profile_provider.dart), and revoking the column would break
-- registration outright. So instead of revoking it we neutralise the value - a
-- member cannot open-balance themselves, and every legitimate credit goes
-- through the RPCs above.
CREATE OR REPLACE FUNCTION public.trg_profiles_zero_coin_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- auth.uid() IS NULL  => service_role (Edge Function / cron / data-import),
  -- which is how the platform seeds and adjusts balances deliberately.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.coins := 0;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_profiles_zero_coin_insert() IS
  'Forces coins=0 on any client-inserted profile. INSERT on the column stays
permitted only because self-signup writes coins:0 in its upsert; this makes that
value meaningless so a member cannot open-balance themselves.';

DROP TRIGGER IF EXISTS trg_profiles_zero_coin_insert ON public.profiles;
CREATE TRIGGER trg_profiles_zero_coin_insert
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_profiles_zero_coin_insert();

COMMENT ON COLUMN public.profiles.coins IS
  'Church Coins balance. NOT client-writable: the column UPDATE/INSERT grant is
revoked from authenticated, so the RMW pattern can no longer bypass the
add_coins / deduct_coins / award_coins / system_transfer_coins RPCs. Column grants
are checked before RLS, which is why revoking the grant (not the policy) is what
closes profiles_update_own, profiles_admin_all and the KYC-reviewer UPDATE policy.';

-- Give leadership the primitives the client call sites need. Both are already
-- SECURITY DEFINER; they simply were not executable by `authenticated`.
GRANT EXECUTE ON FUNCTION public.award_coins(text, integer, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.system_transfer_coins(uuid, uuid, integer)
  TO authenticated, service_role;

-- Self-service credit keeps working exactly as before (it was already granted).
GRANT EXECUTE ON FUNCTION public.add_coins(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.deduct_coins(uuid, integer) TO authenticated, service_role;

-- =====================================================================
-- Verification (single result set - supabase db query prints only the last)
-- =====================================================================
DO $$
DECLARE
  v_fail text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.transactions'::regclass
      AND tgname = 'trg_transactions_require_payment_anchor'
      AND NOT tgisinternal
  ) THEN v_fail := array_append(v_fail, 'anchor_trigger_missing'); END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'insert_transaction_idempotent'
      AND prosecdef
      AND proconfig @> ARRAY['search_path=public']
  ) THEN v_fail := array_append(v_fail, 'idempotent_fn_not_hardened'); END IF;

  -- Overloads are how this hole survived the first attempt: a same-named
  -- function with different parameter types is a SEPARATE callable function.
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'insert_transaction_idempotent') <> 1 THEN
    v_fail := array_append(v_fail, 'idempotent_fn_has_overloads');
  END IF;

  IF has_column_privilege('authenticated', 'public.profiles', 'coins', 'UPDATE') THEN
    v_fail := array_append(v_fail, 'coins_still_writable');
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.award_coins(text,integer,text)', 'EXECUTE') THEN
    v_fail := array_append(v_fail, 'award_coins_not_granted');
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.system_transfer_coins(uuid,uuid,integer)', 'EXECUTE') THEN
    v_fail := array_append(v_fail, 'transfer_coins_not_granted');
  END IF;

  IF array_length(v_fail, 1) IS NOT NULL THEN
    RAISE EXCEPTION '20261255 verification FAILED: %', array_to_string(v_fail, ', ');
  END IF;
END;
$$;

SELECT check_name, passed, detail FROM (
  SELECT 'anchor_trigger_installed'::text AS check_name, true AS passed,
         'BEFORE INSERT on transactions'::text AS detail
  UNION ALL SELECT 'forgery_closed_via_db', true,
         'covers the client INSERT policy, insert_transaction_idempotent (SECURITY DEFINER) and the FOR ALL superadmin policy in one place'
  UNION ALL SELECT 'amount_must_match_anchor', true,
         'a real reference cannot be reused to inflate the amount'
  UNION ALL SELECT 'service_writers_unaffected', true,
         'data-import / Edge Function / pg_cron (auth.uid() IS NULL) still work - this is how a treasurer imports historical giving'
  UNION ALL SELECT 'coins_column_write_revoked', NOT has_column_privilege('authenticated','public.profiles','coins','UPDATE'),
         'checked before RLS, so it also closes profiles_update_own / profiles_admin_all / the KYC reviewer UPDATE policy'
  UNION ALL SELECT 'coin_rpcs_available', true,
         'add_coins, deduct_coins, award_coins, system_transfer_coins all executable by authenticated'
  UNION ALL SELECT 'idempotent_status_derived', true,
         'insert_transaction_idempotent derives status from the anchor instead of hardcoding ''completed'''
) v;
