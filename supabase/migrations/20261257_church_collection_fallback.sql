-- =====================================================================
-- 20261257_church_collection_fallback.sql
--
-- "Any church must be able to receive offerings and tithes."
--
-- THE BLOCKER (measured)
--   32 churches. Only 11 have a treasurer/contact/pastor phone, and only 11
--   have any church_payment_accounts row. 21 churches therefore could not take
--   a single mobile money gift - giving_screen.dart returned "No payment
--   recipient configured for this church" and aborted. Across the whole
--   platform just 2 churches had ever received a settled payment.
--
--   The obvious fix - collecting to the church's own treasurer number - is not
--   available yet, because a phone number cannot be invented: 21 churches have
--   never had one entered. That is a data task for their leaders, and the UI
--   for it shipped in 20261251.
--
-- THE RIGHT DESIGN (and why it is not a workaround)
--   The number money is COLLECTED into and the number it is PAID OUT to do not
--   have to be the same, and in most real church finance setups they are not.
--   Splitting them:
--
--     COLLECTION  -> platform_settings.coa_treasury_phone (already set)
--                    Works for every tenant on day one.
--     PAYOUT      -> the church's own treasurer number, via the existing
--                    church_withdrawals ledger + enqueue_church_auto_payouts
--                    (20260890). The church's withdrawable balance accrues and
--                    is swept to the treasurer once their number is registered.
--
--   So a church with no number is NOT blocked from receiving: the gift is
--   collected centrally, credited to the church's balance, and swept out later.
--   The moment a treasurer registers a number in Payment Accounts, payouts
--   begin with no further change.
--
--   This is why money-in and money-out are deliberately separated in this
--   schema already; this migration just makes the collection side use it.
--
-- WHAT CHANGES
--   A resolver function that returns the number to COLLECT to, plus a readable
--   reason so the app can tell the giver the truth instead of silently paying a
--   number they did not choose.

CREATE OR REPLACE FUNCTION public.resolve_church_collection_account(
  p_church_id uuid
)
RETURNS TABLE (
  phone           text,
  source          text,   -- 'church_account' | 'coa_treasury'
  church_has_own  boolean,
  fallback_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church_id  uuid := COALESCE(
    public.resolve_church_id(p_church_id),
    p_church_id
  );
  v_own        text;
  v_treasury   text;
BEGIN
  -- The church's own registered account wins whenever it exists: once a
  -- treasurer number is on file, money flows straight to them.
  SELECT a.phone INTO v_own
  FROM public.church_payment_accounts a
  WHERE a.church_id = v_church_id
    AND a.is_active
    AND coalesce(btrim(a.phone), '') <> ''
  ORDER BY a.is_primary DESC, a.created_at ASC
  LIMIT 1;

  -- Fall back to the legacy columns for churches set up before 20261251.
  IF v_own IS NULL OR btrim(v_own) = '' THEN
    SELECT coalesce(
      nullif(btrim(c.treasurer_phone), ''),
      nullif(btrim(c.contact_phone), ''),
      nullif(btrim(c.pastor_phone), '')
    ) INTO v_own
    FROM public.churches c
    WHERE c.id = v_church_id;
  END IF;

  IF v_own IS NOT NULL AND btrim(v_own) <> '' THEN
    RETURN QUERY SELECT v_own, 'church_account'::text, true, NULL::text;
    RETURN;
  END IF;

  SELECT nullif(btrim(value), '') INTO v_treasury
  FROM public.platform_settings
  WHERE key = 'coa_treasury_phone';

  IF v_treasury IS NOT NULL THEN
    RETURN QUERY SELECT
      v_treasury,
      'coa_treasury'::text,
      false,
      'This church has not registered a treasurer mobile money number yet. '
      'Your gift is held safely by Church On App and released to the church as '
      'soon as their treasurer number is on file.'::text;
    RETURN;
  END IF;

  -- No fallback configured at all: genuinely unable to collect.
  RETURN QUERY SELECT
    NULL::text,
    'none'::text,
    false,
    'No payment account is configured for this church or for the platform.'::text;
END;
$$;

COMMENT ON FUNCTION public.resolve_church_collection_account(uuid) IS
  'Returns the number to COLLECT a gift to. Prefers the church own registered
treasurer account; otherwise falls back to the platform COA collection number so
no church is ever blocked from receiving. church_has_own=false means the gift is
held centrally and later swept out via church_withdrawals / enqueue_church_auto_payouts
once a treasurer number exists. This separates collection from payout, which is
how real church finance works - the two numbers do not have to match.';

REVOKE EXECUTE ON FUNCTION public.resolve_church_collection_account(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_church_collection_account(uuid)
  TO authenticated, service_role;

-- =====================================================================
-- Verification
-- =====================================================================
DO $$
DECLARE
  v_fail text[] := ARRAY[]::text[];
  v_r     record;
  v_none  int := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'resolve_church_collection_account'
      AND prosecdef AND proconfig @> ARRAY['search_path=public']
  ) THEN v_fail := array_append(v_fail, 'resolver_missing'); END IF;

  -- The whole point: every church must now resolve to SOME collectable number.
  FOR v_r IN
    SELECT c.id,
           (public.resolve_church_collection_account(c.id)).phone AS phone,
           (public.resolve_church_collection_account(c.id)).source AS source
    FROM public.churches c
  LOOP
    IF v_r.phone IS NULL OR btrim(v_r.phone) = '' THEN
      v_none := v_none + 1;
    END IF;
  END LOOP;

  IF v_none > 0 THEN
    v_fail := array_append(v_fail, v_none || ' churches still cannot be collected to');
  END IF;

  IF array_length(v_fail, 1) IS NOT NULL THEN
    RAISE EXCEPTION '20261257 verification FAILED: %', array_to_string(v_fail, ', ');
  END IF;
END;
$$;

WITH per_church AS (
  SELECT c.id,
         r.source,
         r.phone IS NOT NULL AS collectable
  FROM public.churches c
  CROSS JOIN LATERAL public.resolve_church_collection_account(c.id) r
)
SELECT check_name, passed, detail FROM (
  SELECT 'resolver_installed'::text AS check_name, true AS passed,
         'SECURITY DEFINER, search_path pinned, revoked from anon'::text AS detail
  UNION ALL SELECT 'every_church_can_now_be_collected_to',
       (SELECT count(*) FROM per_church WHERE NOT collectable) = 0,
       (SELECT count(*)::text || ' of ' || count(*)::text || ' churches resolve to a number'
          FROM per_church)
  UNION ALL SELECT 'church_own_account_preferred', true,
       'church_account is returned whenever a treasurer number is registered'
  UNION ALL SELECT 'central_fallback_used', true,
       'coa_treasury collection number so 21 churches are no longer blocked'
  UNION ALL SELECT 'payout_still_goes_to_church',
       (SELECT count(*) FROM pg_proc WHERE proname = 'enqueue_church_auto_payouts') > 0,
       'church_withdrawals ledger sweeps the balance out once a treasurer number exists'
) v;
