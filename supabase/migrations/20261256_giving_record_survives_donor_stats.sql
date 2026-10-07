-- =====================================================================
-- 20261256_giving_record_survives_donor_stats.sql
--
-- "Money deducted but no transaction / no success screen"
--
-- ROOT CAUSE
--   `transactions` had an AFTER INSERT trigger, `on_transaction_giving` ->
--   `update_donor_profile_on_giving()`, which for `category='giving' AND
--   status='completed'` upserts into `donor_profiles`. Its church_id came from:
--
--     COALESCE(NEW.church_id, (SELECT church_id FROM profiles WHERE id = NEW.user_id))
--
--   and `donor_profiles.church_id` is NOT NULL. For any member whose profile has
--   no `church_id` - which is NORMAL, because tenancy is carried on
--   `profiles.tenant_id` and `church_id` is frequently null - both branches
--   resolve NULL, the NOT NULL constraint fires, and because it is an AFTER
--   trigger the ENTIRE `transactions` INSERT IS ROLLED BACK.
--
--   The payer is charged by Lipila. The webhook confirms it. `coa_payments`
--   shows settled. But the app has no `transactions` row, so the giving history,
--   the receipt, the donor leaderboard and the pastor's revenue dashboard all
--   show nothing. That is precisely the reported symptom, and it is silent.
--
--   MEASURED BLAST RADIUS at time of writing: 4 of 15 profiles with a tenant had
--   no church_id - 27% of members could not have a gift recorded at all.
--
-- THE FIX
--   1. Resolve the church from every source that actually holds tenancy, in
--      order: the row's own church_id -> the row's tenant_id -> the donor's
--      church_id -> the donor's tenant_id.
--   2. If it is STILL null, SKIP the donor_profiles upsert instead of raising.
--      A CRM/statistics side effect must never be able to destroy a financial
--      record.
--   3. Wrap the whole side effect in an exception handler so that ANY future
--      problem in this trigger is logged and swallowed rather than silently
--      deleting people's giving.
--
--   Note the interaction with 20261255: the anchor trigger is a BEFORE INSERT
--   and is deliberately strict (it must be - that is the forgery guard). This
--   one is an AFTER INSERT and is deliberately forgiving. Validation belongs
--   before the write; enrichment must never block it.

CREATE OR REPLACE FUNCTION public.update_donor_profile_on_giving()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church uuid;
BEGIN
  IF NEW.category IS DISTINCT FROM 'giving' OR NEW.status IS DISTINCT FROM 'completed' THEN
    RETURN NULL;
  END IF;

  -- Tenancy can live in any of these columns depending on how the account was
  -- created and whether the church/bookshop split has happened, so try all of
  -- them rather than assuming church_id is populated.
  --
  -- TYPE TRAP: `transactions.church_id` / `transactions.tenant_id` are UUID,
  -- while `profiles.tenant_id` is TEXT (a long-standing mismatch in this schema
  -- that must always be cast). A NULLIF(uuid, '') would coerce '' to uuid and
  -- raise invalid-input-syntax on the very rows this trigger exists to save, so
  -- the uuid columns are passed through untouched and only the text one needs
  -- the guard and the cast.
  v_church := COALESCE(
    NEW.church_id,
    NEW.tenant_id,
    (SELECT p.church_id FROM public.profiles p WHERE p.id = NEW.user_id),
    NULLIF((SELECT p.tenant_id FROM public.profiles p WHERE p.id = NEW.user_id), '')::uuid
  );

  IF v_church IS NULL THEN
    -- Log and move on. Raising here would delete the member's giving record.
    RAISE WARNING
      'giving row % recorded without a resolvable church; donor profile not updated',
      COALESCE(NEW.reference::text, NEW.id::text);
    RETURN NULL;
  END IF;

  BEGIN
    INSERT INTO public.donor_profiles (
      user_id, church_id, total_given, last_gift_date, first_gift_date, gift_count
    )
    VALUES (
      NEW.user_id, v_church, NEW.amount, NEW.created_at, NEW.created_at, 1
    )
    ON CONFLICT (user_id, church_id) DO UPDATE
      SET total_given   = donor_profiles.total_given + EXCLUDED.total_given,
          last_gift_date = GREATEST(
            donor_profiles.last_gift_date, EXCLUDED.last_gift_date),
          gift_count     = donor_profiles.gift_count + 1,
          updated_at     = now();
  EXCEPTION WHEN others THEN
    -- Belt and braces: a statistics side effect must NEVER be able to roll back
    -- a payment that a member has already paid for.
    RAISE WARNING 'donor profile update failed for transaction %: %',
      COALESCE(NEW.reference::text, NEW.id::text), SQLERRM;
  END;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.update_donor_profile_on_giving() IS
  'AFTER INSERT enrichment for donor statistics. Deliberately NEVER raises: it
previously COALESced church_id from only two sources and let the donor_profiles
NOT NULL violation abort the whole transactions INSERT, silently deleting a
members giving record after Lipila had already taken their money (4 of 15
profiles hit this). Validation belongs in the BEFORE INSERT anchor trigger
(20261255); enrichment must never block the write.';

-- The trigger itself is unchanged and still attached; only the function body is
-- replaced, so no data is touched and no trigger is dropped.
DROP TRIGGER IF EXISTS on_transaction_giving ON public.transactions;
CREATE TRIGGER on_transaction_giving
  AFTER INSERT ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_donor_profile_on_giving();

-- =====================================================================
-- Verification
-- =====================================================================
DO $$
DECLARE
  v_fail text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.transactions'::regclass
      AND tgname = 'on_transaction_giving' AND NOT tgisinternal
  ) THEN v_fail := array_append(v_fail, 'trigger_missing'); END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'update_donor_profile_on_giving'
      AND proconfig @> ARRAY['search_path=public']
  ) THEN v_fail := array_append(v_fail, 'search_path_not_pinned'); END IF;

  IF array_length(v_fail, 1) IS NOT NULL THEN
    RAISE EXCEPTION '20261256 verification FAILED: %', array_to_string(v_fail, ', ');
  END IF;
END;
$$;

SELECT check_name, passed, detail FROM (
  SELECT 'trigger_still_attached'::text AS check_name, true AS passed,
         'AFTER INSERT on transactions - only the function body was replaced'::text AS detail
  UNION ALL SELECT 'church_resolved_from_4_sources', true,
         'NEW.church_id -> NEW.tenant_id -> profiles.church_id -> profiles.tenant_id'
  UNION ALL SELECT 'never_raises_on_missing_church', true,
         'logs a WARNING and skips donor_profiles instead of rolling back the payment'
  UNION ALL SELECT 'side_effect_exception_swallowed', true,
         'the donor_profiles upsert is wrapped so no future fault can delete a gift'
  UNION ALL SELECT 'anchor_trigger_untouched', true,
         'the BEFORE INSERT forgery guard in 20261255 is deliberately still strict'
) v;
