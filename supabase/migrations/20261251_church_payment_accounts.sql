-- ============================================================================
-- Church payment accounts — the mobile-money numbers donations are PAID TO
-- ============================================================================
-- WHY
-- A church cannot receive a single kwacha of giving until somebody tells the
-- platform which mobile-money number the money should land on. The app already
-- knew how to *resolve* that number — `giving_screen.dart` reads
--     tenant.treasurerPhone ?? tenant.contactPhone ?? tenant.pastorPhone
-- and shows "No payment recipient configured for this church" when all three
-- are empty — but there was NO SCREEN ANYWHERE that could write those columns.
-- `churches.treasurer_phone` is read in six places and written by none.
--
-- Verified on the live database before writing this migration:
--   * `churches` HAS `treasurer_phone`, `pastor_phone`, `contact_phone` (text)
--   * 21 of 32 churches had NEITHER `treasurer_phone` NOR `contact_phone`
--     => those churches could not receive giving AT ALL. Not a settings bug —
--     a dead feature for two thirds of the network.
--
-- WHAT THIS ADDS
-- A proper, multi-account register instead of three loose phone columns:
--
--   purpose = 'treasurer'     the church treasurer (tithes + offerings)
--   purpose = 'pastor'        the pastor (fallback)
--   purpose = 'bishop'        the overseeing bishop. The bishop is an
--                             ORGANISATION-level officer, but a branch that has
--                             no treasurer still needs a number someone
--                             controls, hence the new `churches.bishop_phone`.
--   purpose = 'organization'  the church's own published number
--                             (`churches.contact_phone`) or the conference
--                             remittance number.
--
-- Each purpose may hold SEVERAL numbers (a treasurer has two phones), exactly
-- one of which is the PRIMARY — the one money is actually sent to. That mirrors
-- giving_screen's precedence chain, which is why the primary is mirrored back
-- into the legacy columns.
--
-- BACKWARD COMPATIBILITY — THE CRITICAL INTEGRATION POINT
-- `giving_screen.dart` (and `giving_widget.dart`, `my_pledges_screen.dart`,
-- `church_payout_service.dart`, `tithe_card_screen.dart`, …) read the three
-- legacy `churches` columns. Nothing there changes. A trigger
-- (`sync_church_payment_account_to_churches`) mirrors the primary active
-- account of each purpose into its column:
--
--     treasurer     -> churches.treasurer_phone   (1st in the giving chain)
--     pastor        -> churches.pastor_phone      (3rd in the giving chain)
--     bishop        -> churches.bishop_phone      (new column)
--     organization  -> churches.contact_phone     (2nd in the giving chain)
--
-- so setting a treasurer account makes giving start working immediately, with no
-- app change and no redeploy. The same value is ALSO written by the client
-- helper `ChurchPaymentAccountsService.syncPrimaryToChurchesRow`, so the mirror
-- holds even if the RPC is bypassed.
--
-- The mirror is deliberately one-directional and non-destructive: it never
-- blanks a legacy column unless that column still mirrors an account of the
-- same purpose, so a number entered by any other route is never destroyed.
--
-- SECURITY
-- - This table is where "where does the money go" lives, so it is treated as
--   financial data: any member of the church may READ it (the Give tab has to
--   be able to show where a gift is going), only leadership of THAT church may
--   write it, and every write is audited.
-- - No policy anywhere uses `USING (true)` or `WITH CHECK (true)`.
-- - `anon` holds no grant on the table at all.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Columns on `churches`
-- ---------------------------------------------------------------------------
-- `bishop_phone` is new: the bishop is chosen at ORGANISATION level, so there is
-- no bishop number anywhere on the branch row.
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS bishop_phone TEXT;

-- Marks the treasurer number as checked against the holder. Default FALSE and
-- never flipped by a client: only platform staff (see
-- `verify_church_treasurer_phone`) may set it, so a church cannot self-certify.
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS treasurer_phone_verified BOOLEAN NOT NULL DEFAULT false;

-- The giving chain resolves a recipient on every gift; this keeps it indexed.
CREATE INDEX IF NOT EXISTS idx_churches_treasurer_phone
  ON public.churches (treasurer_phone) WHERE treasurer_phone IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 1. Network detection (server side)
-- ---------------------------------------------------------------------------
-- ZICTA prefixes: MTN 096/076, Airtel 097/077, Zamtel 095/075.
-- Accepts `+260…`, `260…`, a leading `0`, or a bare 9-digit number. Returns NULL
-- for anything unrecognised — the caller decides what to do, we never guess a
-- network from a half-typed prefix (a wrong network means a failed collection).
CREATE OR REPLACE FUNCTION public.zambian_momo_network(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  WITH cleaned AS (
    SELECT regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g') AS d
  ), local AS (
    SELECT CASE
             WHEN d LIKE '260%' AND length(d) >= 11 THEN '0' || substr(d, 4)
             WHEN length(d) = 9                   THEN '0' || d
             ELSE d
           END AS l
      FROM cleaned
  )
  SELECT CASE
           WHEN left(l, 3) IN ('096', '076') THEN 'mtn'
           WHEN left(l, 3) IN ('097', '077') THEN 'airtel'
           WHEN left(l, 3) IN ('095', '075') THEN 'zamtel'
           ELSE NULL
         END
    FROM local;
$$;
-- Pure server helper: no client needs to call it.
REVOKE ALL ON FUNCTION public.zambian_momo_network(text) FROM PUBLIC, anon;
-- Kept available to the service role: cron jobs and admin tooling run as
-- service_role, not as a signed-in church leader.
GRANT EXECUTE ON FUNCTION public.zambian_momo_network(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. The register
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.church_payment_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The church the money is collected FOR. Cascades so a deleted church does
  -- not leave live payout numbers behind.
  church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,

  -- Which slot this number occupies. See the header for the giving precedence.
  purpose TEXT NOT NULL
    CHECK (purpose IN ('treasurer', 'pastor', 'bishop', 'organization')),

  -- Optional human label, e.g. "Treasurer (main)" / "Deputy treasurer".
  label TEXT,

  -- The mobile-money number itself. Stored exactly as entered by leadership so
  -- the church can recognise it; the Lipila settlement chain re-derives the
  -- E.164 form server-side and never trusts this column for routing.
  phone TEXT NOT NULL CHECK (btrim(phone) <> ''),

  -- Denormalised for the UI chip + operator confidence. NULL when the prefix is
  -- not a recognised Zambian one (landline / international number).
  network TEXT CHECK (network IN ('mtn', 'airtel', 'zamtel')),

  -- At most ONE active primary per (church_id, purpose) — enforced by a partial
  -- unique index below, not just by convention.
  is_primary BOOLEAN NOT NULL DEFAULT false,
  is_active  BOOLEAN NOT NULL DEFAULT true,

  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_church_payment_accounts_church
  ON public.church_payment_accounts (church_id, purpose, is_primary);

-- Only one ACTIVE primary per purpose: the number money is actually sent to.
CREATE UNIQUE INDEX IF NOT EXISTS ux_church_payment_accounts_primary
  ON public.church_payment_accounts (church_id, purpose)
  WHERE is_primary AND is_active;

-- The same number cannot be entered twice for the same purpose. Keeps the
-- backfill below re-runnable and stops a leadership member adding 096… five times.
CREATE UNIQUE INDEX IF NOT EXISTS ux_church_payment_accounts_number
  ON public.church_payment_accounts (church_id, purpose, btrim(phone));

ALTER TABLE public.church_payment_accounts ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. Membership / permission helpers
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER + `SET search_path = public`: these are called from inside RLS
-- policies, where the caller holds no direct privilege on `profiles`. They are
-- STABLE and read-only. Note the grant at the end of this section — revoking
-- from anon while keeping `authenticated` able to EXECUTE is what lets the
-- policies use them at all.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_church_payment_account_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
      IN ('superadmin', 'super_admin', 'coa_employee', 'employee'),
    false);
$$;

CREATE OR REPLACE FUNCTION public.is_my_church_payment_accounts_church(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    EXISTS (
      SELECT 1
        FROM public.profiles p
        JOIN public.churches c ON c.id = p_church_id
       WHERE p.id = auth.uid()
         -- `profiles.tenant_id` is TEXT while `churches.id`/`tenants.id` are
         -- UUID, hence the ::text on both sides (text = uuid does not exist and
         -- a handler that swallows it makes the feature silently do nothing).
         -- Seeded data shares ONE uuid between tenants and churches; a church
         -- registered after the split stores the tenancy id on
         -- `churches.tenant_id`. Accept either so both shapes resolve.
         AND (p.tenant_id::text = p_church_id::text
              OR p.tenant_id::text = c.tenant_id::text)
    ),
    false);
$$;

-- READ: any member of the church. The Give tab must be able to show where a
-- gift is being sent, which means every member needs to read the register.
CREATE OR REPLACE FUNCTION public.can_view_church_payment_accounts(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_church_payment_account_staff()
      OR public.is_my_church_payment_accounts_church(p_church_id);
$$;

-- WRITE: leadership of THAT church only. Members, ushers, visitors and
-- bookshop staff are all excluded.
CREATE OR REPLACE FUNCTION public.can_manage_church_payment_accounts(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    public.is_church_payment_account_staff()
    OR (
      public.is_my_church_payment_accounts_church(p_church_id)
      AND (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
          IN ('pastor', 'bishop', 'apostle', 'prophet', 'admin',
              'general_secretary', 'general_treasurer', 'treasurer', 'leader')
    ),
    false);
$$;

REVOKE ALL ON FUNCTION public.is_church_payment_account_staff() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_my_church_payment_accounts_church(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_view_church_payment_accounts(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_church_payment_accounts(uuid) FROM PUBLIC, anon;

-- The three policy helpers are referenced by name in the policies below, so
-- `authenticated` must be able to EXECUTE them (`anon` and `PUBLIC` do not).
GRANT EXECUTE ON FUNCTION public.is_church_payment_account_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_my_church_payment_accounts_church(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_church_payment_accounts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_church_payment_accounts(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
-- SECURITY: Supabase grants `authenticated` ALL privileges on newly created
-- tables, so the grants are narrowed explicitly and RLS is the real gate. An
-- unauthenticated visitor holds nothing at all on this table.
REVOKE ALL ON public.church_payment_accounts FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.church_payment_accounts TO authenticated;

DROP POLICY IF EXISTS "church_payment_accounts_read" ON public.church_payment_accounts;
CREATE POLICY "church_payment_accounts_read"
  ON public.church_payment_accounts FOR SELECT TO authenticated
  USING (public.can_view_church_payment_accounts(church_id));

DROP POLICY IF EXISTS "church_payment_accounts_insert" ON public.church_payment_accounts;
CREATE POLICY "church_payment_accounts_insert"
  ON public.church_payment_accounts FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_church_payment_accounts(church_id));

DROP POLICY IF EXISTS "church_payment_accounts_update" ON public.church_payment_accounts;
CREATE POLICY "church_payment_accounts_update"
  ON public.church_payment_accounts FOR UPDATE TO authenticated
  USING (public.can_manage_church_payment_accounts(church_id))
  WITH CHECK (public.can_manage_church_payment_accounts(church_id));

DROP POLICY IF EXISTS "church_payment_accounts_delete" ON public.church_payment_accounts;
CREATE POLICY "church_payment_accounts_delete"
  ON public.church_payment_accounts FOR DELETE TO authenticated
  USING (public.can_manage_church_payment_accounts(church_id));

-- ---------------------------------------------------------------------------
-- 5. `updated_at`
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_church_payment_accounts_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
-- Trigger body only: invoked by the engine, never called by a client.
REVOKE ALL ON FUNCTION public.touch_church_payment_accounts_updated_at() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_church_payment_accounts_updated_at
  ON public.church_payment_accounts;
CREATE TRIGGER trg_church_payment_accounts_updated_at
  BEFORE UPDATE ON public.church_payment_accounts
  FOR EACH ROW EXECUTE FUNCTION public.touch_church_payment_accounts_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Mirror the primary back into the legacy `churches` columns
-- ---------------------------------------------------------------------------
-- This is what makes the feature work with ZERO changes to giving_screen.dart.
-- AFTER INSERT/UPDATE/DELETE so every write path is covered (direct client
-- write, the `set_church_primary_account` RPC, or the backfill below).
--
-- Split in two: the reconciliation itself is reusable, so a row that MOVED slot
-- (its purpose edited from 'treasurer' to 'pastor', say) can reconcile the slot
-- it left behind too — otherwise `churches.treasurer_phone` would keep pointing
-- at a number that is no longer a treasurer number.

CREATE OR REPLACE FUNCTION public.mirror_church_payment_account(
  p_church_id UUID,
  p_purpose TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_col     TEXT;
  v_primary TEXT;
  v_current TEXT;
BEGIN
  IF p_church_id IS NULL OR p_purpose IS NULL THEN RETURN; END IF;

  v_col := CASE p_purpose
             WHEN 'treasurer'    THEN 'treasurer_phone'
             WHEN 'pastor'       THEN 'pastor_phone'
             WHEN 'bishop'       THEN 'bishop_phone'
             WHEN 'organization' THEN 'contact_phone'
           END;
  IF v_col IS NULL THEN RETURN; END IF;

  SELECT a.phone INTO v_primary
    FROM public.church_payment_accounts a
   WHERE a.church_id = p_church_id
     AND a.purpose = p_purpose
     AND a.is_primary
     AND a.is_active
   ORDER BY a.updated_at DESC
   LIMIT 1;

  EXECUTE format('SELECT %I FROM public.churches WHERE id = $1', v_col)
    INTO v_current USING p_church_id;

  IF v_primary IS NOT NULL THEN
    -- Only write when it actually differs, so this never fires a pointless
    -- UPDATE on `churches` (and never churns `updated_at`).
    IF v_current IS DISTINCT FROM v_primary THEN
      EXECUTE format('UPDATE public.churches SET %I = $1 WHERE id = $2', v_col)
        USING v_primary, p_church_id;
    END IF;
    RETURN;
  END IF;

  -- No active primary for this slot (deactivated, demoted, moved away or
  -- deleted). Blank the legacy column ONLY if it still mirrors one of this
  -- slot's accounts — a number entered by some other route must never be
  -- silently destroyed.
  IF v_current IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.church_payment_accounts a
     WHERE a.church_id = p_church_id
       AND a.purpose = p_purpose
       AND btrim(a.phone) = btrim(v_current)
  ) THEN
    EXECUTE format('UPDATE public.churches SET %I = NULL WHERE id = $1', v_col)
      USING p_church_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.mirror_church_payment_account(uuid, text)
  FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.sync_church_payment_account_to_churches()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- COALESCE(NEW, OLD) covers DELETE, where NEW is not assigned.
  PERFORM public.mirror_church_payment_account(
            COALESCE(NEW.church_id, OLD.church_id),
            COALESCE(NEW.purpose,  OLD.purpose));

  -- The row changed slot (or was deleted, where NEW is NULL and this is simply a
  -- harmless second pass). Reconcile the old slot too.
  IF OLD.church_id IS DISTINCT FROM NEW.church_id
     OR OLD.purpose IS DISTINCT FROM NEW.purpose THEN
    PERFORM public.mirror_church_payment_account(OLD.church_id, OLD.purpose);
  END IF;

  -- `RETURN NULL` is correct for an AFTER trigger; the value is ignored.
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_church_payment_account_to_churches() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_sync_church_payment_account_to_churches
  ON public.church_payment_accounts;
CREATE TRIGGER trg_sync_church_payment_account_to_churches
  AFTER INSERT OR UPDATE OR DELETE ON public.church_payment_accounts
  FOR EACH ROW EXECUTE FUNCTION public.sync_church_payment_account_to_churches();

-- ---------------------------------------------------------------------------
-- 7. RPC: make one account the primary for its purpose
-- ---------------------------------------------------------------------------
-- Clearing siblings and setting the new one cannot be done with a plain client
-- UPDATE, because the partial unique index is enforced per row-statement: a
-- single `UPDATE ... SET is_primary = (id = x)` would violate it on whichever
-- sibling is processed first. Two ordered statements avoid the race, and the
-- RPC is also the only place the permission check is written once.
CREATE OR REPLACE FUNCTION public.set_church_primary_account(p_account_id UUID)
RETURNS public.church_payment_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.church_payment_accounts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_row
    FROM public.church_payment_accounts
   WHERE id = p_account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment account not found'; END IF;

  IF NOT public.can_manage_church_payment_accounts(v_row.church_id) THEN
    RAISE EXCEPTION 'only leadership of this church may set the primary payment account';
  END IF;

  -- Demote first, then promote: promoting first would trip the partial unique
  -- index while the previous primary is still flagged.
  UPDATE public.church_payment_accounts
     SET is_primary = false,
         updated_at = now()
   WHERE church_id = v_row.church_id
     AND purpose = v_row.purpose
     AND is_primary
     AND id <> p_account_id;

  UPDATE public.church_payment_accounts
     SET is_primary = true,
         is_active = true,
         updated_at = now()
   WHERE id = p_account_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_church_primary_account(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_church_primary_account(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_church_primary_account(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 8. Admin-only: verify the treasurer number
-- ---------------------------------------------------------------------------
-- A church must not be able to self-certify that it owns a number, so this is
-- platform staff only and `authenticated` is explicitly revoked — the role check
-- inside is the second lock, not the first.
CREATE OR REPLACE FUNCTION public.verify_church_treasurer_phone(
  p_church_id UUID,
  p_verified BOOLEAN DEFAULT true
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT public.is_church_payment_account_staff() THEN
    RAISE EXCEPTION 'only Church On App staff may verify a treasurer number';
  END IF;

  SELECT a.phone INTO v_phone
    FROM public.church_payment_accounts a
   WHERE a.church_id = p_church_id
     AND a.purpose = 'treasurer'
     AND a.is_primary
     AND a.is_active
   LIMIT 1;

  IF v_phone IS NULL THEN
    RAISE EXCEPTION 'this church has no active primary treasurer account to verify';
  END IF;

  UPDATE public.churches
     SET treasurer_phone_verified = p_verified
   WHERE id = p_church_id;

  RETURN p_verified;
END;
$$;
REVOKE ALL ON FUNCTION public.verify_church_treasurer_phone(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
-- Only the service role (COA back-office / admin tooling) may verify.
GRANT EXECUTE ON FUNCTION public.verify_church_treasurer_phone(uuid, boolean)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 9. Server-side mirror of the giving precedence chain
-- ---------------------------------------------------------------------------
-- Read-only, and the single place the chain is written down. The client
-- (`giving_screen.dart`) applies the same order; keeping both means a support
-- engineer can ask the database where a gift would go.
CREATE OR REPLACE FUNCTION public.resolve_church_giving_phone(p_church_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone          TEXT;
  v_treasurer_phone TEXT;
  v_contact_phone   TEXT;
  v_pastor_phone    TEXT;
BEGIN
  IF NOT public.can_view_church_payment_accounts(p_church_id) THEN
    RAISE EXCEPTION 'you may not read the payment accounts of this church';
  END IF;

  -- The register wins over the legacy columns: it is the maintained source.
  SELECT a.phone INTO v_phone
    FROM public.church_payment_accounts a
   WHERE a.church_id = p_church_id
     AND a.is_active
   ORDER BY (CASE a.purpose
               WHEN 'treasurer'    THEN 1
               WHEN 'organization' THEN 2
               WHEN 'pastor'       THEN 3
               WHEN 'bishop'       THEN 4
               ELSE 9
               END),
             a.is_primary DESC
   LIMIT 1;

  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  -- Nothing in the register (a church that predates this feature): fall back to
  -- the loose columns, in giving_screen.dart's exact order.
  SELECT c.treasurer_phone, c.contact_phone, c.pastor_phone
    INTO v_treasurer_phone, v_contact_phone, v_pastor_phone
    FROM public.churches c
   WHERE c.id = p_church_id;

  RETURN COALESCE(v_treasurer_phone, v_contact_phone, v_pastor_phone);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_church_giving_phone(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_church_giving_phone(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_church_giving_phone(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 10. Audit. Where giving money lands is exactly what gets disputed later.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_church_audit_church_payment_accounts
  ON public.church_payment_accounts;
CREATE TRIGGER trg_church_audit_church_payment_accounts
  AFTER INSERT OR UPDATE ON public.church_payment_accounts
  FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture();

-- ---------------------------------------------------------------------------
-- 11. Backfill — do not lose the numbers that already exist.
-- ---------------------------------------------------------------------------
-- 21 of 32 churches have no treasurer and no contact number; the 11 that do
-- have numbers had them typed into the loose columns by hand, with no record of
-- which role owned them. Copy each one into the register as the primary for its
-- purpose. Guarded by NOT EXISTS so re-running is a no-op.
--
-- `organization` <- `contact_phone`: the church's own published number is the
-- giving-chain fallback, and 'organization' is the only remaining purpose slot.
-- It mirrors back into `contact_phone`, so this round-trips unchanged.
--
-- `ON CONFLICT DO NOTHING` covers BOTH unique indexes, so the backfill is safe to
-- re-run after leadership have since changed a primary (the NOT EXISTS guard
-- alone would still try to insert a second primary and blow up).
INSERT INTO public.church_payment_accounts
  (church_id, purpose, label, phone, network, is_primary, is_active)
SELECT c.id, 'treasurer', 'Treasurer', btrim(c.treasurer_phone),
       public.zambian_momo_network(c.treasurer_phone), true, true
  FROM public.churches c
 WHERE c.treasurer_phone IS NOT NULL
   AND btrim(c.treasurer_phone) <> ''
   AND NOT EXISTS (
     SELECT 1 FROM public.church_payment_accounts a
      WHERE a.church_id = c.id
        AND a.purpose = 'treasurer'
        AND btrim(a.phone) = btrim(c.treasurer_phone))
ON CONFLICT DO NOTHING;

INSERT INTO public.church_payment_accounts
  (church_id, purpose, label, phone, network, is_primary, is_active)
SELECT c.id, 'pastor', 'Pastor', btrim(c.pastor_phone),
       public.zambian_momo_network(c.pastor_phone), true, true
  FROM public.churches c
 WHERE c.pastor_phone IS NOT NULL
   AND btrim(c.pastor_phone) <> ''
   AND NOT EXISTS (
     SELECT 1 FROM public.church_payment_accounts a
      WHERE a.church_id = c.id
        AND a.purpose = 'pastor'
        AND btrim(a.phone) = btrim(c.pastor_phone))
ON CONFLICT DO NOTHING;

INSERT INTO public.church_payment_accounts
  (church_id, purpose, label, phone, network, is_primary, is_active)
SELECT c.id, 'organization', 'Church office', btrim(c.contact_phone),
       public.zambian_momo_network(c.contact_phone), true, true
  FROM public.churches c
 WHERE c.contact_phone IS NOT NULL
   AND btrim(c.contact_phone) <> ''
   AND NOT EXISTS (
     SELECT 1 FROM public.church_payment_accounts a
      WHERE a.church_id = c.id
        AND a.purpose = 'organization'
        AND btrim(a.phone) = btrim(c.contact_phone))
ON CONFLICT DO NOTHING;

-- NOTE ON `treasurer_phone_verified`: it is left at its default `false`. A number
-- typed into a loose column by hand has never been checked against the person
-- who holds the SIM, so nothing is verified by this migration. Only platform
-- staff can flip it, via `verify_church_treasurer_phone`.

-- ---------------------------------------------------------------------------
-- 12. Refuse to ship a feature that looks present and cannot collect money.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  n     INT;
  v_bad INT;
BEGIN
  IF to_regclass('public.church_payment_accounts') IS NULL THEN
    RAISE EXCEPTION 'church_payment_accounts was not created';
  END IF;

  -- The new columns must exist, or the mirror trigger raises on its first run.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'churches'
       AND column_name = 'bishop_phone'
  ) THEN
    RAISE EXCEPTION 'churches.bishop_phone was not added';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'churches'
       AND column_name = 'treasurer_phone_verified'
  ) THEN
    RAISE EXCEPTION 'churches.treasurer_phone_verified was not added';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'church_payment_accounts'
       AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'church_payment_accounts must have RLS enabled';
  END IF;

  -- No blanket policy. A `USING (true)` here would let every signed-in member
  -- redirect where 100% of the network's giving is sent.
  SELECT count(*) INTO n
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'church_payment_accounts'
     AND (qual LIKE '%true%' OR with_check LIKE '%true%');
  IF n > 0 THEN
    RAISE EXCEPTION 'church_payment_accounts has a blanket (true) policy';
  END IF;

  -- `anon` must hold nothing at all.
  IF EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND table_name = 'church_payment_accounts'
       AND grantee = 'anon'
  ) THEN
    RAISE EXCEPTION 'anon holds a grant on church_payment_accounts';
  END IF;

  -- Exactly one active primary per (church, purpose).
  SELECT count(*) INTO v_bad
    FROM (
      SELECT church_id, purpose
        FROM public.church_payment_accounts
       WHERE is_primary AND is_active
       GROUP BY church_id, purpose
      HAVING count(*) > 1
    ) d;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '% (church, purpose) pair(s) have more than one active primary', v_bad;
  END IF;

  -- The whole point: every mirrored primary must be visible in the column the
  -- giving chain reads. If this fails, giving is still dead.
  SELECT count(*) INTO v_bad
    FROM public.church_payment_accounts a
   WHERE a.is_primary AND a.is_active
     AND a.purpose = 'treasurer'
     AND NOT EXISTS (
       SELECT 1 FROM public.churches c
        WHERE c.id = a.church_id
          AND c.treasurer_phone = a.phone);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '% primary treasurer account(s) are not mirrored into churches.treasurer_phone', v_bad;
  END IF;

  -- Backfill must not have lost anything.
  SELECT count(*) INTO v_bad
    FROM public.churches c
   WHERE c.treasurer_phone IS NOT NULL
     AND btrim(c.treasurer_phone) <> ''
     AND NOT EXISTS (
       SELECT 1 FROM public.church_payment_accounts a
        WHERE a.church_id = c.id AND a.purpose = 'treasurer'
          AND btrim(a.phone) = btrim(c.treasurer_phone));
  IF v_bad > 0 THEN
    RAISE EXCEPTION '% existing treasurer number(s) were lost in the backfill', v_bad;
  END IF;

  -- Both RPCs present and not callable anonymously.
  SELECT count(*) INTO n
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public'
     AND p.proname IN ('set_church_primary_account', 'verify_church_treasurer_phone',
                       'resolve_church_giving_phone', 'zambian_momo_network');
  IF n <> 4 THEN
    RAISE EXCEPTION 'expected 4 functions, found %', n;
  END IF;

  IF has_function_privilege('anon', 'public.set_church_primary_account(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can call set_church_primary_account';
  END IF;
  IF has_function_privilege('authenticated',
                            'public.verify_church_treasurer_phone(uuid, boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'a church can verify its own treasurer number';
  END IF;

  RAISE NOTICE 'church_payment_accounts ready: % account(s) backfilled',
    (SELECT count(*) FROM public.church_payment_accounts);
END;
$$;