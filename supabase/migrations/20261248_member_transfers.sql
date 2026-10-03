-- ============================================================================
-- Member transfers between churches
-- ============================================================================
-- WHY THIS IS THE BIGGEST MISSING PIECE FOR A ZAMBIAST PASTOR
-- When a member moves from one church to another this is a real, paper-based
-- event: the outgoing pastor issues a transfer letter, the member carries it to
-- the incoming church, and BOTH churches need a durable record. Today that
-- lives in a cupboard as a sheet of paper, and the member's history effectively
-- restarts at zero in the new church.
--
-- This is not a reporting nicety. It is the mechanism by which a pastor
-- establishes that someone is a member in good standing - which is what they
-- need for a marriage licence, a scholarship, a job reference, or a burial
-- claim. Churches that cannot produce it are the ones that lose members.
--
-- SCOPE
-- Covers both directions:
--   OUTBOUND  a member of this church is leaving
--   INBOUND   a member arriving from another church, presenting a letter
--   INTERNAL  moving between house fellowships / cells of the same church
--
-- The interchurch case is the one that pays off at network scale: a transfer
-- into a COA church from a partner church is also how the network grows, so
-- this doubles as the interchurch membership handshake.
--
-- DESIGN NOTES
-- - `letter_no` is generated from a per-tenant sequence so a church can quote
--   it over the phone ("TRF/ROC/2026/0007") the way they quote a receipt.
-- - Approving an OUTBOUND transfer is what actually moves the member: the
--   server reassigns profiles.tenant_id. Never done client-side.
-- - Both churches can read a transfer involving them; nobody else can.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.member_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Church the member is leaving. NULL for an inbound transfer where we only
  -- know the originating church by name.
  from_tenant_id TEXT,
  from_church_name TEXT,

  -- Church receiving the member. NULL while an outbound transfer is only
  -- requested and no destination is chosen yet.
  to_tenant_id TEXT,
  to_church_name TEXT,

  -- 'outbound' = leaving this church, 'inbound' = arriving here,
  -- 'internal' = moving between cells/house fellowships, same church.
  direction TEXT NOT NULL DEFAULT 'outbound'
    CHECK (direction IN ('outbound', 'inbound', 'internal')),

  -- 'requested' -> 'approved' -> 'completed', or 'declined'/'cancelled'.
  status TEXT NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested', 'approved', 'declined', 'cancelled', 'completed')),

  -- Human-quotable reference, e.g. TRF/ROC/2026/0007.
  letter_no TEXT,

  reason TEXT,
  notes TEXT,

  requested_by UUID REFERENCES public.profiles(id),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by UUID REFERENCES public.profiles(id),
  decided_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,

  -- Snapshot of the member's state at transfer time, so the receiving church
  -- sees where they came from without querying the old church (which may not
  -- share its data with us).
  member_name TEXT,
  member_phone TEXT,
  membership_years INTEGER,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_member_transfers_from
  ON public.member_transfers (from_tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_member_transfers_to
  ON public.member_transfers (to_tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_member_transfers_member
  ON public.member_transfers (member_id, created_at DESC);
-- A church must not mint the same letter number twice.
CREATE UNIQUE INDEX IF NOT EXISTS ux_member_transfers_letter_no
  ON public.member_transfers (letter_no) WHERE letter_no IS NOT NULL;

ALTER TABLE public.member_transfers ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Reads: leadership of either church involved.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "member_transfers_read_parties" ON public.member_transfers;
CREATE POLICY "member_transfers_read_parties"
  ON public.member_transfers FOR SELECT
  USING (
    from_tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR to_tenant_id::text  = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
         IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
  );

-- ---------------------------------------------------------------------------
-- Helper: is the caller leadership of this tenant?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_tenant_leadership(p_tenant TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
     WHERE id = auth.uid()
       AND tenant_id::text = p_tenant
       AND role IN ('pastor','bishop','apostle','prophet','admin','leader',
                    'department_leader','general_secretary','general_treasurer',
                    'treasurer')
  );
$$;
REVOKE ALL ON FUNCTION public.is_tenant_leadership(text) FROM anon;

-- ---------------------------------------------------------------------------
-- Per-tenant letter sequence, so the number a pastor quotes is unique.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.next_transfer_letter_no(p_tenant TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seq INT;
  v_code TEXT;
  v_church TEXT;
BEGIN
  SELECT COALESCE(next_id_sequence('transfer_letter_' || p_tenant), '0001')
    INTO v_seq;

  -- Short church code for the human-readable part, e.g. ROC.
  SELECT UPPER(LEFT(REGEXP_REPLACE(COALESCE(name, 'COA'), '[^A-Za-z]', '', 'g'), 3))
    INTO v_code
    FROM public.tenants WHERE id::text = p_tenant;
  v_code := COALESCE(NULLIF(v_code, ''), 'COA');

  RETURN 'TRF/' || v_code || '/' || TO_CHAR(now(), 'YYYY') || '/'
         || LPAD(v_seq::TEXT, 4, '0');
END;
$$;
REVOKE ALL ON FUNCTION public.next_transfer_letter_no(text) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- Request a transfer. Leadership of the originating church only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_member_transfer(
  p_member_id UUID,
  p_direction TEXT,
  p_to_tenant TEXT DEFAULT NULL,
  p_to_church_name TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.member_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_actor_tenant TEXT;
  v_role TEXT;
  v_from_tenant TEXT;
  v_from_name TEXT;
  v_dir TEXT := lower(COALESCE(p_direction, 'outbound'));
  v_letter TEXT;
  v_row public.member_transfers;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT tenant_id::text, role INTO v_actor_tenant, v_role
    FROM public.profiles WHERE id = v_uid;

  -- Staff may act for any church; otherwise you must lead the church the
  -- member currently belongs to.
  IF v_role NOT IN ('superadmin', 'super_admin', 'coa_employee', 'employee') THEN
    IF NOT public.is_tenant_leadership(v_actor_tenant) THEN
      RAISE EXCEPTION 'only church leadership may request a transfer';
    END IF;
  END IF;

  SELECT tenant_id::text INTO v_from_tenant
    FROM public.profiles WHERE id = p_member_id;
  IF v_from_tenant IS NULL THEN
    RAISE EXCEPTION 'member not found';
  END IF;

  IF v_dir NOT IN ('outbound', 'inbound', 'internal') THEN
    RAISE EXCEPTION 'unknown direction %', p_direction;
  END IF;

  SELECT name INTO v_from_name FROM public.tenants WHERE id::text = v_from_tenant;

  -- An outbound transfer needs a real destination up front, otherwise it can be
  -- requested and only discovered to be undeliverable at approval time.
  IF v_dir = 'outbound' AND p_to_tenant IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id::text = p_to_tenant) THEN
      RAISE EXCEPTION 'destination church % does not exist', p_to_tenant;
    END IF;
  END IF;

  v_letter := public.next_transfer_letter_no(v_from_tenant);

  INSERT INTO public.member_transfers
    (member_id, from_tenant_id, from_church_name, to_tenant_id, to_church_name,
     direction, status, letter_no, reason, notes, requested_by,
     member_name, member_phone, membership_years)
  VALUES (
    p_member_id,
    CASE WHEN v_dir = 'inbound' THEN NULL ELSE v_from_tenant END,
    CASE WHEN v_dir = 'inbound' THEN p_to_church_name ELSE v_from_name END,
    CASE WHEN v_dir = 'inbound' THEN v_from_tenant ELSE p_to_tenant END,
    p_to_church_name,
    v_dir, 'requested', v_letter, p_reason, p_notes, v_uid,
    (SELECT full_name FROM public.profiles WHERE id = p_member_id),
    (SELECT phone_number FROM public.profiles WHERE id = p_member_id),
    EXTRACT(YEAR FROM age(NOW(), (SELECT created_at FROM public.profiles
                                   WHERE id = p_member_id)))::INT
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.request_member_transfer(uuid, text, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_member_transfer(uuid, text, text, text, text, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- Approve + complete. Approving an OUTBOUND transfer is what actually moves
-- the member: the server reassigns profiles.tenant_id. Never client-side.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decide_member_transfer(
  p_transfer_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.member_transfers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_t public.member_transfers;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_t FROM public.member_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'transfer not found'; END IF;
  IF v_t.status <> 'requested' THEN
    RAISE EXCEPTION 'transfer already %', v_t.status;
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('superadmin', 'super_admin', 'coa_employee', 'employee') THEN
    IF NOT (public.is_tenant_leadership(v_t.from_tenant_id)
            OR public.is_tenant_leadership(v_t.to_tenant_id)) THEN
      RAISE EXCEPTION 'only leadership of either church may decide this transfer';
    END IF;
  END IF;

  IF NOT p_approve THEN
    UPDATE public.member_transfers
       SET status = 'declined', decided_by = v_uid, decided_at = now(),
           notes = COALESCE(p_notes, notes), updated_at = now()
     WHERE id = p_transfer_id
    RETURNING * INTO v_t;
    RETURN v_t;
  END IF;

  -- Approving: move the member when leaving this church.
  IF v_t.direction = 'outbound' AND v_t.to_tenant_id IS NOT NULL THEN
    -- Fail with a readable message before touching profiles. `profiles` carries
    -- a `tenant_uuid` FK maintained by a sync trigger, so a mistyped
    -- destination would otherwise surface as a raw foreign-key violation deep
    -- in the UPDATE - which tells a pastor nothing.
    IF NOT EXISTS (
      SELECT 1 FROM public.tenants WHERE id::text = v_t.to_tenant_id
    ) THEN
      RAISE EXCEPTION 'destination church % does not exist', v_t.to_tenant_id;
    END IF;

    UPDATE public.profiles SET tenant_id = v_t.to_tenant_id WHERE id = v_t.member_id;
  END IF;

  UPDATE public.member_transfers
     SET status = 'completed',
         decided_by = v_uid,
         decided_at = now(),
         completed_at = now(),
         notes = COALESCE(p_notes, notes),
         updated_at = now()
   WHERE id = p_transfer_id
  RETURNING * INTO v_t;

  RETURN v_t;
END;
$$;
REVOKE ALL ON FUNCTION public.decide_member_transfer(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_member_transfer(uuid, boolean, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- This table is itself auditable: a transfer is a change of church membership,
-- which is exactly the kind of thing that must be traceable.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_church_audit_member_transfers ON public.member_transfers;
CREATE TRIGGER trg_church_audit_member_transfers
  AFTER INSERT OR UPDATE ON public.member_transfers
  FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture();

-- ---------------------------------------------------------------------------
-- Fail loudly rather than ship something that looks right and is not.
-- ---------------------------------------------------------------------------
DO $$
DECLARE n INT;
BEGIN
  IF to_regclass('public.member_transfers') IS NULL THEN
    RAISE EXCEPTION 'member_transfers was not created';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public' AND p.proname = 'request_member_transfer'
  ) THEN
    RAISE EXCEPTION 'request_member_transfer missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'member_transfers'
       AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  ) THEN
    RAISE EXCEPTION 'member_transfers must be written only via its RPCs';
  END IF;
END;
$$;