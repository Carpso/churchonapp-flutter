-- ============================================================================
-- Church governance: officers, ministerial credentials, branch licensing
-- ============================================================================
-- THREE REGISTERS A ZAMBIAST CHURCH KEEPS IN A CUPBOARD, NOT IN A DATABASE
--
-- (A) CHURCH OFFICERS            the elders / deacons / deaconesses roll
-- (B) MINISTERIAL CREDENTIALS    who is actually ORDAINED, and by whom
-- (C) BRANCH LICENSES            which branches of an organisation may run
--
-- These are three registers with three DIFFERENT authorities, and confusing them
-- is precisely the governance failure they exist to prevent:
--
--   * a CHURCH APPOINTS its elders and deacons      (local authority: pastor)
--   * a CONFERENCE ORDAINS a minister               (denominational: bishop)
--   * an ORGANISATION LICENSES its branches         (network: bishop/secretary/
--                                                     treasurer of that org)
--
-- Today all three live in a paper register book. So "is this man an ordained
-- elder, or did the pastor just give him the title?", "which of my 14 branches are
-- actually licensed?", and "who is on my exco and when does their term end?" cannot
-- be answered without fetching the book.
--
-- ---------------------------------------------------------------------------
-- (B) WHY ORDINATION IS ENFORCED AGAINST THE BISHOP, NOT THE PASTOR
-- ---------------------------------------------------------------------------
-- This is the whole point of the credential register, so it is enforced in the
-- DATABASE and not merely described in the UI:
--
-- A local pastor can APPOINT a deacon. A local pastor CANNOT ORDAIN one.
-- Ordination is conferred by the conference / denomination - in practice by the
-- bishop, or an apostle, prophet, or the conference general secretary or general
-- treasurer acting under the same authority. If a client could mint an
-- ordination, the credential would be worth nothing: a certificate any pastor can
-- issue is not a credential, it is a title.
--
-- `can_issue_ordination(p_church_id)` is therefore the gate, and it is checked by
-- grant, renew, revoke AND reinstate:
--   * profiles.role IN ('bishop','apostle','prophet',
--                        'general_secretary','general_treasurer'), or
--   * platform staff (superadmin / super_admin / coa_employee / employee), or
--   * the caller IS `organizations.bishop_id` of the church's OWN organisation.
--
-- The third clause exists because of the 20261215 finding: an organisation created
-- with a bishop as `organizations.bishop_id` failed purely role-based gates.
-- Ordination authority belongs to the OFFICE, so the office is consulted as well.
-- It is deliberately `bishop_id` ONLY - an organisation's secretary and treasurer
-- are financial/administrative officers and confer no ordination.
--
-- ---------------------------------------------------------------------------
-- (B) WHY A REVOKED CREDENTIAL MUST KEEP ITS HISTORY
-- ---------------------------------------------------------------------------
-- A credential can be revoked AFTER the person has already served - possibly for
-- years, in another church, with a credential number quoted on a letter somebody
-- is relying on. Therefore:
--
--   * rows are NEVER deleted and a number is NEVER reused. `credential_number` is
--     unique, so a revoked number still resolves to the person who held it.
--   * revocation is a STATE (`status` plus `revoked_at` / `revoked_by` /
--     `revocation_reason`), not a deletion, and the REASON IS MANDATORY. A bare
--     revocation with no stated cause tells the holder nothing and tells the next
--     church nothing; it is not a record.
--   * `ministerial_credential_events` is APPEND-ONLY, one row per grant / renew /
--     revoke / suspend / reinstate, and has no INSERT, UPDATE or DELETE policy at
--     all - only the SECURITY DEFINER RPCs can add to it.
--   * revoking a credential does NOT end the person's church appointment. They stay
--     on `church_officers` until the church ends it. Ordination and appointment are
--     separate acts by separate authorities, and collapsing them would let a
--     conference decision silently strip a local church's roll - or the reverse.
--   * a suspension can be lifted (`reinstate_ministerial_credential`); a REVOCATION
--     IS FINAL, and restoring it means granting a NEW credential (which keeps both
--     rows). Renewal deliberately refuses to launder a revocation.
--
-- ---------------------------------------------------------------------------
-- (C) WHY THE BRANCH-LICENCE GATE IS STRICTER THAN `is_org_owner`
-- ---------------------------------------------------------------------------
-- `is_org_owner(p_org_id)` (20261215) is TRUE for anybody whose church is merely
-- LINKED to the organisation - which includes every branch pastor. Reusing it here
-- would let a branch pastor licence their own branch, i.e. self-certify.
-- `is_branch_license_authority(p_org_id)` accepts ONLY:
--   * platform staff (superadmin / super_admin / coa_employee / employee), or
--   * the caller IS bishop_id / secretary_id / treasurer_id of THAT organisation.
--
-- ---------------------------------------------------------------------------
-- EXPIRY IS DERIVED, NEVER WRITTEN BY A TRIGGER
-- ---------------------------------------------------------------------------
-- Nothing here flips a status to 'expired' on a schedule. Both a credential and a
-- licence whose date has simply passed are still stored as 'active'/'licensed', and
-- the reader treats the passed date as expired. The reason: the status change IS
-- the record. A trigger that rewrites it at 03:00 would either bypass the
-- permission check that governs every other transition, or write an event nobody
-- authorised. An expiry becomes a real state when somebody acts on it
-- (`revoke_ministerial_credential(p_status => 'expired')`), and that action is
-- audited like any other.
--
-- ---------------------------------------------------------------------------
-- SECURITY POSTURE (uniform across all three registers)
-- ---------------------------------------------------------------------------
-- - RLS on. `anon` holds NO grant on any of the four tables.
-- - `authenticated` holds SELECT ONLY. There is not one INSERT/UPDATE/DELETE
--   policy anywhere, AND the write privilege itself is revoked - Postgres checks
--   table grants BEFORE RLS, so omitting a policy alone is not enough. Every state
--   transition is a SECURITY DEFINER RPC that re-checks the actor and appends to the
--   audit trail.
-- - `service_role` keeps write access for back-office repair and any future
--   backfill; no RPC writes behind it.
-- - Every SECURITY DEFINER function has `SET search_path = public` and is revoked
--   from `anon`. The RPCs are granted to `authenticated` + `service_role`; the RLS
--   helper functions are granted to `authenticated` because policies name them.
-- - `church_audit_capture()` triggers put every insert/update into
--   `church_audit_log`, so the tenant-visible activity trail records these changes
--   without any client cooperation.
-- - `profiles.tenant_id` is TEXT while `churches.id` / `tenants.id` /
--   `organizations.id` are UUID: every comparison casts `::text`, because
--   `text = uuid` does not exist and a handler that swallows it makes a feature
--   silently do nothing forever.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Remote-config keys
-- ---------------------------------------------------------------------------
-- A branch licence is annual in practice, but "annual" is a BUSINESS value: change
-- it in `platform_settings` and every future issue and renewal picks it up without
-- a deploy. `ON CONFLICT DO NOTHING` keeps this migration re-runnable and never
-- overwrites a value COA has already edited.
INSERT INTO public.platform_settings (key, value) VALUES
  ('branch_license_validity_months',       '12'),
  ('branch_license_renewal_lead_days',     '30'),
  -- 0 means "no automatic expiry": ordination is normally for life. A conference
  -- that does renew annually sets 12 and the grant RPC fills expires_on from it.
  ('ministerial_credential_validity_months', '0')
ON CONFLICT (key) DO NOTHING;

-- ===========================================================================
-- 1. (A) CHURCH OFFICERS
-- ===========================================================================
-- One row per appointment. The paper equivalent is the elders / deacons /
-- deaconesses page of the church register book, signed and dated.
CREATE TABLE IF NOT EXISTS public.church_officers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Denormalised tenancy id, so the audit trigger and the read policies have a TEXT
  -- key to compare against `profiles.tenant_id` without re-deriving it.
  tenant_id TEXT,

  role TEXT NOT NULL CHECK (role IN ('elder', 'deacon', 'deaconess')),

  appointed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  appointed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Terms are how a Zambian church actually runs its officers board: a fixed term,
  -- then a deliberate renewal. term_end NULL means "no end date set".
  term_start DATE NOT NULL DEFAULT CURRENT_DATE,
  term_end DATE,

  -- 'transferred' is a distinct end state from 'inactive': the person moved to
  -- another church (see 20261248 member_transfers) and this church's roll is closed
  -- behind them. A transfer does NOT end the appointment by itself - a person may
  -- transfer and still finish a term - so the church does it here, explicitly.
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'deceased', 'transferred')),

  -- Executive / officers board membership (the exco that runs things between
  -- meetings). This is what decides who is in the officers' meeting.
  is_exco_member BOOLEAN NOT NULL DEFAULT false,

  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_church_officers_church
  ON public.church_officers (church_id, status, role);
CREATE INDEX IF NOT EXISTS idx_church_officers_member
  ON public.church_officers (member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_church_officers_tenant
  ON public.church_officers (tenant_id, role);
-- The product rule: ONE ACTIVE row per (church, person, role). Someone may be an
-- elder AND a deacon in the same church - that happens - but they cannot hold two
-- concurrent active terms in the SAME office.
CREATE UNIQUE INDEX IF NOT EXISTS ux_church_officers_active
  ON public.church_officers (church_id, member_id, role)
  WHERE status = 'active';
-- Term ends are queried to warn about upcoming retirements, so keep them indexed.
CREATE INDEX IF NOT EXISTS idx_church_officers_term_end
  ON public.church_officers (church_id, term_end)
  WHERE status = 'active' AND term_end IS NOT NULL;

ALTER TABLE public.church_officers ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 2. (B) MINISTERIAL CREDENTIALS + APPEND-ONLY EVENT LOG
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.ministerial_credentials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The person who HOLDS the credential. It is a person, not a church: someone can
  -- be ordained before any church has them.
  holder_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- 'ordained'   = full ordination (deacon / deaconess / elder / pastor / bishop)
  -- 'licensed'   = recognised to preach or teach (local preacher, evangelist,
  --                teacher)
  -- 'accredited' = in training / recognised provisionally
  credential_type TEXT NOT NULL
    CHECK (credential_type IN ('ordained', 'licensed', 'accredited')),

  -- The office or function the credential confers. Separate from credential_type
  -- because a conference grades the same three titles differently.
  ministry_role TEXT NOT NULL
    CHECK (ministry_role IN ('deacon', 'deaconess', 'elder', 'pastor', 'bishop',
                             'local_preacher', 'evangelist', 'teacher')),

  -- Unique, quoted on certificates, and NEVER reused: a revoked number must still
  -- resolve to the person who held it.
  credential_number TEXT,

  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'revoked', 'suspended', 'expired')),

  -- Who conferred it, as written on the certificate - e.g. "Zambia Conference of
  -- the UPC", "Rock of Ages Fellowship", "Bishop A. Mwale".
  issuing_authority TEXT NOT NULL,

  -- NULL = a CONFERENCE-WIDE credential (the holder is ordained to the
  -- denomination, not to one local church). This is the common case for a bishop
  -- ordaining a pastor, so it must be supported rather than worked around.
  church_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,

  -- Denormalised tenancy id, mirroring church_audit_capture's expectation. NULL for
  -- a conference-wide credential, which is correct: it belongs to no church.
  tenant_id TEXT,

  issued_on DATE NOT NULL DEFAULT CURRENT_DATE,
  -- NULL = no expiry (ordination for life, the normal case).
  expires_on DATE,

  -- Revocation is a STATE, never a deletion. For a SUSPENSION these three columns
  -- carry the suspension; `status` is what distinguishes the two.
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  revocation_reason TEXT,

  granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  notes TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_credential_holder
  ON public.ministerial_credentials (holder_user_id, issued_on DESC);
CREATE INDEX IF NOT EXISTS idx_credential_church
  ON public.ministerial_credentials (church_id, status)
  WHERE church_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_credential_status
  ON public.ministerial_credentials (status, expires_on);

-- A number identifies exactly one credential, forever.
CREATE UNIQUE INDEX IF NOT EXISTS ux_credential_number
  ON public.ministerial_credentials (btrim(credential_number))
  WHERE credential_number IS NOT NULL AND btrim(credential_number) <> '';
-- A holder may hold several credentials (ordained deacon AND licensed teacher) but
-- never two ACTIVE credentials of the same type and office. Partial on
-- status = 'active' so revoking frees the slot for a fresh grant while the revoked
-- row survives as history.
CREATE UNIQUE INDEX IF NOT EXISTS ux_credential_active_holder
  ON public.ministerial_credentials (holder_user_id, credential_type, ministry_role)
  WHERE status = 'active';

ALTER TABLE public.ministerial_credentials ENABLE ROW LEVEL SECURITY;

-- The append-only trail: one row per grant / renew / revoke / suspend / reinstate.
CREATE TABLE IF NOT EXISTS public.ministerial_credential_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  credential_id UUID NOT NULL REFERENCES public.ministerial_credentials(id)
    ON DELETE CASCADE,

  event_type TEXT NOT NULL
    CHECK (event_type IN ('granted', 'renewed', 'revoked', 'suspended',
                          'expired', 'reinstated')),

  -- Both sides recorded, so "what was this person's status before?" is never a
  -- guess. from_status is NULL on the first grant.
  from_status TEXT,
  to_status TEXT,

  actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_credential_events_credential
  ON public.ministerial_credential_events (credential_id, created_at);
CREATE INDEX IF NOT EXISTS idx_credential_events_actor
  ON public.ministerial_credential_events (actor_id, created_at DESC);

ALTER TABLE public.ministerial_credential_events ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 3. (C) BRANCH LICENSING / CERTIFICATION
-- ===========================================================================
-- A "branch" is a `churches` row linked to an organisation
-- (`churches.organization_id`). The organisation licenses it. An unlicensed branch
-- is running but not certified by its parent - the exact thing a conference is
-- asked about when it issues letters of good standing.
CREATE TABLE IF NOT EXISTS public.branch_licenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,

  -- Resolved from `churches.organization_id` when the application is submitted. A
  -- branch with no parent cannot be licensed by anybody, so `apply_for_branch_
  -- license` refuses it; the column is nullable only because
  -- `churches.organization_id` is, and an out-of-band insert must not break.
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,

  status TEXT NOT NULL DEFAULT 'unlicensed'
    CHECK (status IN ('unlicensed', 'application_submitted', 'under_review',
                      'licensed', 'suspended', 'revoked')),

  -- Human-quotable application reference, e.g. BRLAPP/ZAMAA/2026/0003.
  application_reference TEXT,

  -- The licensing checklist as a jsonb object of item -> met/unmet:
  --   {"constitution_on_file": true, "pastor_ordinated": true,
  --    "bank_account_open": false, "membership_minimum_met": true}
  -- An explicit FALSE BLOCKS a licence being issued - that is what makes this a
  -- checklist rather than decoration. Absent keys are not required, so a church
  -- lists only what it actually assesses.
  requirements JSONB NOT NULL DEFAULT '{}'::jsonb,

  submitted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  submitted_at TIMESTAMPTZ,

  -- Who RECEIVED the application ("under review") and who DECIDED it. Deliberately
  -- one column for both: in a real conference the secretary receives and the bishop
  -- decides, and the register only needs to show that a decision happened.
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,

  -- Unique, and NOT reused: a revoked licence number must stay traceable.
  license_number TEXT,

  issued_at TIMESTAMPTZ,
  expires_at DATE,
  -- Renewal falls due a month BEFORE expiry, not on the day: that is when the
  -- conference actually chases it.
  renewal_due_at DATE,

  -- Suspension and revocation are states with their own reason, not a blank status -
  -- same reasoning as credentials: the record must say why.
  suspended_at TIMESTAMPTZ,
  suspension_reason TEXT,
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  revocation_reason TEXT,

  decision_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_branch_licenses_church
  ON public.branch_licenses (church_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_branch_licenses_org
  ON public.branch_licenses (organization_id, status)
  WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_branch_licenses_renewals
  ON public.branch_licenses (renewal_due_at)
  WHERE status = 'licensed';

-- One licence number identifies one licence, forever.
CREATE UNIQUE INDEX IF NOT EXISTS ux_branch_license_number
  ON public.branch_licenses (btrim(license_number))
  WHERE license_number IS NOT NULL AND btrim(license_number) <> '';
-- A branch cannot have two applications in flight. A decision (grant, refuse,
-- revoke) closes the open one and releases the slot.
CREATE UNIQUE INDEX IF NOT EXISTS ux_branch_license_open_application
  ON public.branch_licenses (church_id)
  WHERE status IN ('application_submitted', 'under_review');

ALTER TABLE public.branch_licenses ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 4. PERMISSION HELPERS
-- ===========================================================================
-- All SECURITY DEFINER + STABLE + `SET search_path = public`, because they are
-- called from inside RLS policies where the caller holds no direct privilege on
-- `profiles` / `churches` / `organizations`. `authenticated` is granted EXECUTE
-- (policies reference them by name); `anon` and PUBLIC are not.

-- ---------------------------------------------------------------------------
-- `churches.id` -> tenancy id. THE FIDDLE BIT, IN ONE PLACE.
-- ---------------------------------------------------------------------------
-- Seeded data shares ONE uuid between `tenants.id` and `churches.id`, while a
-- church registered after the split stores the tenancy id on
-- `churches.tenant_id`. Both shapes exist in production, so accept either. Every
-- gate below needs this and none of them should re-derive it (20261251 solved the
-- same problem inside `is_my_church_payment_accounts_church`; this is the shared,
-- named version).
CREATE OR REPLACE FUNCTION public.church_tenant_id(p_church_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant TEXT;
BEGIN
  IF p_church_id IS NULL THEN RETURN NULL; END IF;

  -- Newer registrations: the church's own tenancy column.
  SELECT c.tenant_id::text INTO v_tenant
    FROM public.churches c
   WHERE c.id = p_church_id;
  IF v_tenant IS NOT NULL AND v_tenant <> '' THEN RETURN v_tenant; END IF;

  -- Seeded data: tenants.id and churches.id are the same uuid.
  SELECT t.id::text INTO v_tenant
    FROM public.tenants t
   WHERE t.id = p_church_id;
  RETURN v_tenant;
END;
$$;
REVOKE ALL ON FUNCTION public.church_tenant_id(uuid) FROM PUBLIC, anon;

-- WRITE officers: leadership of THAT church, or platform staff. Reuses
-- `is_tenant_leadership` (20261248) rather than re-listing the role set, so a
-- future role change applies here too.
CREATE OR REPLACE FUNCTION public.can_manage_church_officers(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_church_id IS NULL THEN RETURN false; END IF;
  IF public.is_admin_or_employee() THEN RETURN true; END IF;
  RETURN public.is_tenant_leadership(public.church_tenant_id(p_church_id));
END;
$$;
REVOKE ALL ON FUNCTION public.can_manage_church_officers(uuid) FROM PUBLIC, anon;

-- READ officers: any member of that church, plus platform staff. Deliberately
-- WIDER than the discipline register (20261249): an elders / deacons roll is a
-- PUBLIC office roll in a Zambian church - members are expected to know who the
-- elders are - so unlike pastoral care it is not sensitive data.
CREATE OR REPLACE FUNCTION public.can_view_church_officers(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant TEXT;
BEGIN
  IF auth.uid() IS NULL OR p_church_id IS NULL THEN RETURN false; END IF;
  IF public.is_admin_or_employee() THEN RETURN true; END IF;
  v_tenant := public.church_tenant_id(p_church_id);
  RETURN v_tenant = (SELECT p.tenant_id::text
                     FROM public.profiles p WHERE p.id = auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.can_view_church_officers(uuid) FROM PUBLIC, anon;

-- THE ORDINATION GATE. See the header for the full rule. Passing a NULL
-- p_church_id asks the role question alone, which is what a CONFERENCE-WIDE
-- credential (church_id IS NULL) needs.
CREATE OR REPLACE FUNCTION public.can_issue_ordination(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_org  UUID;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;

  -- Platform staff: COA runs the network, so it must be able to record and correct
  -- credentials on a bishop's behalf.
  IF public.is_admin_or_employee() THEN RETURN true; END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = auth.uid();

  -- Denominational authority. Ordination is conferred by the conference, so these
  -- roles carry it wherever they sit in the network - NOT only over their own
  -- organisation. A bishop ordaining a pastor in another branch is normal.
  IF v_role IN ('bishop', 'apostle', 'prophet',
                'general_secretary', 'general_treasurer') THEN
    RETURN true;
  END IF;

  -- The OFFICE as well as the role: the bishop of the church's own organisation,
  -- whose profiles.role may have drifted (the 20261215 failure mode). bishop_id
  -- ONLY - an organisation's secretary and treasurer confer no ordination.
  IF p_church_id IS NOT NULL THEN
    SELECT c.organization_id INTO v_org
      FROM public.churches c
     WHERE c.id = p_church_id;

    IF v_org IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = v_org AND o.bishop_id = auth.uid()
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.can_issue_ordination(uuid) FROM PUBLIC, anon;

-- READ credentials attached to a church: the holder, that church's leadership (a
-- pastor must be able to see their deacon's credential to present it), the
-- organisation's officers, anyone holding ordination authority, and staff.
CREATE OR REPLACE FUNCTION public.can_view_ordinations(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant TEXT;
  v_org    UUID;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF public.is_admin_or_employee() THEN RETURN true; END IF;
  IF public.can_issue_ordination(p_church_id) THEN RETURN true; END IF;

  -- Leadership of the church the credential belongs to.
  v_tenant := public.church_tenant_id(p_church_id);
  IF v_tenant IS NOT NULL
     AND v_tenant = (SELECT p.tenant_id::text FROM public.profiles p
                      WHERE p.id = auth.uid()) THEN
    RETURN true;
  END IF;

  -- Any officer of the church's parent organisation.
  SELECT c.organization_id INTO v_org
    FROM public.churches c
   WHERE c.id = p_church_id;
  IF v_org IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.organizations o
     WHERE o.id = v_org
       AND (o.bishop_id    = auth.uid()
         OR o.secretary_id = auth.uid()
         OR o.treasurer_id = auth.uid())
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.can_view_ordinations(uuid) FROM PUBLIC, anon;

-- THE BRANCH-LICENCE GATE. Deliberately stricter than `is_org_owner` - see header.
CREATE OR REPLACE FUNCTION public.is_branch_license_authority(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_org_id IS NULL THEN RETURN false; END IF;
  IF public.is_admin_or_employee() THEN RETURN true; END IF;

  RETURN EXISTS (
    SELECT 1
      FROM public.organizations o
     WHERE o.id = p_org_id
       AND (o.bishop_id    = auth.uid()
         OR o.secretary_id = auth.uid()
         OR o.treasurer_id = auth.uid())
  );
END;
$$;
REVOKE ALL ON FUNCTION public.is_branch_license_authority(uuid) FROM PUBLIC, anon;

-- READ a licence: the branch's own leadership (they must be able to see WHY they
-- are unlicensed), the parent organisation's officers, and platform staff.
CREATE OR REPLACE FUNCTION public.can_view_branch_license(p_church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org UUID;
BEGIN
  IF auth.uid() IS NULL OR p_church_id IS NULL THEN RETURN false; END IF;
  IF public.is_admin_or_employee() THEN RETURN true; END IF;
  IF public.can_manage_church_officers(p_church_id) THEN RETURN true; END IF;

  SELECT c.organization_id INTO v_org
    FROM public.churches c
   WHERE c.id = p_church_id;
  IF v_org IS NOT NULL AND public.is_branch_license_authority(v_org) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.can_view_branch_license(uuid) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- Either kind of id -> `churches.id`. THE OTHER HALF OF THE FIDDLE BIT.
-- ---------------------------------------------------------------------------
-- The client passes `currentTenantProvider.id`, which is a TENANCY id. Every
-- register here stores `churches.id`, because that is the column with the FKs.
-- For seeded data the two are the SAME uuid, so the mismatch never showed up -
-- but a church registered after the tenancy/church split has two different uuids,
-- and an INSERT then fails with a raw foreign-key violation that says nothing
-- about churches. Resolve it once, in one named place.
--
-- Order matters: a direct `churches.id` hit wins, so a caller that genuinely means
-- a church is never redirected through a second church's tenancy row.
CREATE OR REPLACE FUNCTION public.resolve_church_id(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church UUID;
BEGIN
  IF p_id IS NULL THEN RETURN NULL; END IF;

  SELECT c.id INTO v_church
    FROM public.churches c
   WHERE c.id = p_id
   LIMIT 1;
  IF v_church IS NOT NULL THEN RETURN v_church; END IF;

  -- A tenancy id: find the church that belongs to it.
  SELECT c.id INTO v_church
    FROM public.churches c
   WHERE c.tenant_id = p_id
   ORDER BY c.created_at
   LIMIT 1;

  RETURN v_church;
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_church_id(uuid) FROM PUBLIC, anon;

-- The policy helpers are named inside the policies below, so `authenticated` must
-- be able to EXECUTE them. `anon` and PUBLIC hold nothing.
GRANT EXECUTE ON FUNCTION public.resolve_church_id(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.church_tenant_id(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_church_officers(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_church_officers(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_issue_ordination(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_ordinations(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_branch_license_authority(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_branch_license(uuid) TO authenticated, service_role;

-- ===========================================================================
-- 5. RLS + GRANTS
-- ===========================================================================
-- `anon` holds NOTHING on any of the four tables. `authenticated` holds SELECT
-- ONLY - there is not one INSERT/UPDATE/DELETE policy anywhere, and the write
-- privilege is not merely unused but revoked, so a client cannot go around the RPCs.
REVOKE ALL ON public.church_officers FROM anon;
REVOKE ALL ON public.ministerial_credentials FROM anon;
REVOKE ALL ON public.ministerial_credential_events FROM anon;
REVOKE ALL ON public.branch_licenses FROM anon;

REVOKE ALL ON public.church_officers FROM authenticated;
REVOKE ALL ON public.ministerial_credentials FROM authenticated;
REVOKE ALL ON public.ministerial_credential_events FROM authenticated;
REVOKE ALL ON public.branch_licenses FROM authenticated;

GRANT SELECT ON public.church_officers TO authenticated;
GRANT SELECT ON public.ministerial_credentials TO authenticated;
GRANT SELECT ON public.ministerial_credential_events TO authenticated;
GRANT SELECT ON public.branch_licenses TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.church_officers, public.ministerial_credentials,
     public.ministerial_credential_events, public.branch_licenses
  TO service_role;

-- --- officers ---------------------------------------------------------------
DROP POLICY IF EXISTS "church_officers_read" ON public.church_officers;
CREATE POLICY "church_officers_read"
  ON public.church_officers FOR SELECT TO authenticated
  USING (public.can_view_church_officers(church_id));

-- --- credentials ------------------------------------------------------------
-- Split in two because a CONFERENCE-WIDE credential (church_id IS NULL) belongs to
-- no church: it is visible to its holder, to platform staff, to anyone holding
-- ordination authority, and to any bishop of any organisation - and to nobody else.
-- A local pastor does not get to read the conference-wide roll.
DROP POLICY IF EXISTS "ministerial_credentials_read_church" ON public.ministerial_credentials;
CREATE POLICY "ministerial_credentials_read_church"
  ON public.ministerial_credentials FOR SELECT TO authenticated
  USING (church_id IS NOT NULL AND (
         holder_user_id = auth.uid()
      OR public.can_view_ordinations(church_id)
  ));

DROP POLICY IF EXISTS "ministerial_credentials_read_conference" ON public.ministerial_credentials;
CREATE POLICY "ministerial_credentials_read_conference"
  ON public.ministerial_credentials FOR SELECT TO authenticated
  USING (church_id IS NULL AND (
         holder_user_id = auth.uid()
      OR public.can_issue_ordination(NULL)
      OR EXISTS (SELECT 1 FROM public.organizations o WHERE o.bishop_id = auth.uid())
  ));

-- --- credential events ------------------------------------------------------
-- Mirrors the credential read rules exactly, so the history is never more visible
-- than the credential it describes. SELECT only, forever: there is no INSERT policy
-- because the trail is written by the RPCs and nothing may amend it.
DROP POLICY IF EXISTS "ministerial_credential_events_read" ON public.ministerial_credential_events;
CREATE POLICY "ministerial_credential_events_read"
  ON public.ministerial_credential_events FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
      FROM public.ministerial_credentials mc
     WHERE mc.id = credential_id
       AND (
            (mc.church_id IS NOT NULL AND public.can_view_ordinations(mc.church_id))
         OR (mc.church_id IS NULL
             AND (mc.holder_user_id = auth.uid()
                  OR public.can_issue_ordination(NULL)
                  OR EXISTS (SELECT 1 FROM public.organizations o
                              WHERE o.bishop_id = auth.uid())))
       )
  ));

-- --- branch licences --------------------------------------------------------
-- Visible to the branch itself and to its parent organisation. A SIBLING branch
-- cannot read it: a licence is between one branch and one organisation, and a
-- conference that cannot hold its branches to account is not supervising them.
DROP POLICY IF EXISTS "branch_licenses_read" ON public.branch_licenses;
CREATE POLICY "branch_licenses_read"
  ON public.branch_licenses FOR SELECT TO authenticated
  USING (public.can_view_branch_license(church_id));

-- ===========================================================================
-- 6. updated_at TRIGGERS
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.touch_church_governance_updated_at()
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
REVOKE ALL ON FUNCTION public.touch_church_governance_updated_at() FROM PUBLIC, anon;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['church_officers', 'ministerial_credentials',
                            'branch_licenses'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_%I_updated_at ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_touch_%I_updated_at
         BEFORE UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.touch_church_governance_updated_at()', t, t);
  END LOOP;
END;
$$;

-- ===========================================================================
-- 7. REFERENCE NUMBER GENERATORS
-- ===========================================================================
-- A number a secretary can quote over the phone ("is your licence number
-- BRL/ZAMAA/2026/0003?"), which is how these things are actually used. A number
-- typed in by hand is still accepted - a conference may already have printed it -
-- but a blank one is minted here so the register is never anonymous.

CREATE OR REPLACE FUNCTION public.next_ordination_credential_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seq TEXT;
BEGIN
  SELECT COALESCE(next_id_sequence('ministerial_credential'), '0001') INTO v_seq;
  RETURN 'ORD/' || TO_CHAR(now(), 'YYYY') || '/' || v_seq;
END;
$$;
REVOKE ALL ON FUNCTION public.next_ordination_credential_number() FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.next_branch_license_number(p_org_id UUID, p_kind TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_kind TEXT := lower(COALESCE(p_kind, 'license'));
  v_seq  TEXT;
  v_code TEXT;
  v_pfx  TEXT;
BEGIN
  IF p_org_id IS NULL THEN
    RAISE EXCEPTION 'a licence number needs an organisation';
  END IF;
  IF v_kind NOT IN ('application', 'license') THEN
    RAISE EXCEPTION 'unknown reference kind %', p_kind;
  END IF;

  v_pfx := CASE v_kind WHEN 'application' THEN 'BRLAPP' ELSE 'BRL' END;

  SELECT COALESCE(next_id_sequence('branch_' || v_kind || '_' || p_org_id), '0001')
    INTO v_seq;

  -- Short organisation code, e.g. ZAMAA.
  SELECT UPPER(LEFT(REGEXP_REPLACE(COALESCE(name, 'COA'), '[^A-Za-z]', '', 'g'), 5))
    INTO v_code
    FROM public.organizations
   WHERE id = p_org_id;
  v_code := COALESCE(NULLIF(v_code, ''), 'COA');

  RETURN v_pfx || '/' || v_code || '/' || TO_CHAR(now(), 'YYYY') || '/' || v_seq;
END;
$$;
REVOKE ALL ON FUNCTION public.next_branch_license_number(uuid, text) FROM PUBLIC, anon;

-- ===========================================================================
-- 8. (A) OFFICER RPCs
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.appoint_officer(
  p_church_id UUID,
  p_member_id UUID,
  p_role TEXT,
  p_term_start DATE DEFAULT NULL,
  p_term_end DATE DEFAULT NULL,
  p_is_exco_member BOOLEAN DEFAULT false,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.church_officers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_tenant TEXT;
  v_member_tenant TEXT;
  v_start DATE := COALESCE(p_term_start, CURRENT_DATE);
  v_church UUID;
  v_row public.church_officers;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_role NOT IN ('elder', 'deacon', 'deaconess') THEN
    RAISE EXCEPTION 'unknown officer role %', p_role;
  END IF;

  -- The client sends the TENANCY id; the table stores `churches.id`.
  v_church := public.resolve_church_id(p_church_id);
  IF v_church IS NULL THEN
    RAISE EXCEPTION 'church % not found', p_church_id;
  END IF;

  IF NOT public.can_manage_church_officers(v_church) THEN
    RAISE EXCEPTION 'only church leadership may appoint an officer';
  END IF;

  SELECT public.church_tenant_id(v_church) INTO v_tenant;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'church % has no tenancy record', v_church;
  END IF;

  -- An officer is a member of the church that appoints them. Without this the roll
  -- drifts into a list of people who actually attend somewhere else.
  SELECT p.tenant_id::text INTO v_member_tenant
    FROM public.profiles p WHERE p.id = p_member_id;
  IF v_member_tenant IS NULL OR v_member_tenant = '' THEN
    RAISE EXCEPTION 'member not found';
  END IF;
  IF v_member_tenant <> v_tenant THEN
    RAISE EXCEPTION 'this person is not a member of this church';
  END IF;

  IF p_term_end IS NOT NULL AND p_term_end < v_start THEN
    RAISE EXCEPTION 'the term cannot end before it starts';
  END IF;

  -- The partial unique index rejects this anyway, but a readable error naming the
  -- office is worth far more than "duplicate key value violates unique constraint
  -- ux_church_officers_active", which tells a pastor nothing.
  IF EXISTS (
    SELECT 1 FROM public.church_officers
     WHERE church_id = v_church
       AND member_id = p_member_id
       AND role = p_role
       AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'this person already holds an active appointment as % of this church',
      p_role;
  END IF;

  INSERT INTO public.church_officers
    (church_id, member_id, tenant_id, role, appointed_by, appointed_at,
     term_start, term_end, status, is_exco_member, notes)
  VALUES
    (v_church, p_member_id, v_tenant, p_role, v_uid, now(),
     v_start, p_term_end, 'active', COALESCE(p_is_exco_member, false), p_notes)
  RETURNING * INTO v_row;

  -- The audit row: `trg_church_audit_church_officers` writes to church_audit_log on
  -- this INSERT, with the actor taken from auth.uid() inside the trigger. A client
  -- can add context but can never omit the fact.

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.appoint_officer(uuid, uuid, text, date, date, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.appoint_officer(uuid, uuid, text, date, date, boolean, text)
  TO authenticated, service_role;

-- End an appointment. The row is NEVER deleted: a roll that silently loses a
-- deceased elder, or a deacon who transferred, cannot answer "who served here and
-- when" - the question a conference, a scholarship panel or a family asks years
-- later.
CREATE OR REPLACE FUNCTION public.end_officer_appointment(
  p_officer_id UUID,
  p_status TEXT DEFAULT 'inactive',
  p_notes TEXT DEFAULT NULL
)
RETURNS public.church_officers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.church_officers;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_status NOT IN ('inactive', 'deceased', 'transferred') THEN
    RAISE EXCEPTION 'unknown end state %', p_status;
  END IF;

  SELECT * INTO v_row FROM public.church_officers WHERE id = p_officer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'appointment not found'; END IF;
  IF v_row.status <> 'active' THEN
    RAISE EXCEPTION 'this appointment is already %', v_row.status;
  END IF;

  IF NOT public.can_manage_church_officers(v_row.church_id) THEN
    RAISE EXCEPTION 'only church leadership may end an appointment';
  END IF;

  UPDATE public.church_officers
     SET status = p_status,
         -- A term that was already dated keeps the date it was planned to run to,
         -- which is the whole value of keeping the row. Only an open-ended
         -- appointment gets an end date, and it gets today's.
         term_end = COALESCE(term_end, CURRENT_DATE),
         notes = COALESCE(p_notes, notes),
         updated_at = now()
   WHERE id = p_officer_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.end_officer_appointment(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_officer_appointment(uuid, text, text)
  TO authenticated, service_role;

-- ===========================================================================
-- 9. (B) CREDENTIAL RPCs
-- ===========================================================================
-- Private helper: append one line to the credential trail. Never called by a client
-- - every state transition below funnels through it, so a grant, a renew, a revoke
-- and a reinstatement are recorded identically and none can be forgotten.
CREATE OR REPLACE FUNCTION public.append_credential_event(
  p_credential_id UUID,
  p_event_type TEXT,
  p_from_status TEXT,
  p_to_status TEXT,
  p_reason TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ministerial_credential_events
    (credential_id, event_type, from_status, to_status, actor_id, reason, metadata)
  VALUES
    (p_credential_id, p_event_type, p_from_status, p_to_status,
     auth.uid(), p_reason, COALESCE(p_metadata, '{}'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.append_credential_event(uuid, text, text, text, text, jsonb)
  FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.grant_ministerial_credential(
  p_holder_user_id UUID,
  p_credential_type TEXT,
  p_ministry_role TEXT,
  p_church_id UUID DEFAULT NULL,
  p_credential_number TEXT DEFAULT NULL,
  p_issued_on DATE DEFAULT NULL,
  p_expires_on DATE DEFAULT NULL,
  p_issuing_authority TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.ministerial_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_number TEXT;
  v_authority TEXT;
  v_tenant TEXT;
  v_expires DATE;
  v_months TEXT;
  v_church UUID;
  v_row public.ministerial_credentials;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_credential_type NOT IN ('ordained', 'licensed', 'accredited') THEN
    RAISE EXCEPTION 'unknown credential type %', p_credential_type;
  END IF;
  IF p_ministry_role NOT IN ('deacon', 'deaconess', 'elder', 'pastor', 'bishop',
                             'local_preacher', 'evangelist', 'teacher') THEN
    RAISE EXCEPTION 'unknown ministry role %', p_ministry_role;
  END IF;

  -- The client sends the TENANCY id; the table stores `churches.id`.
  v_church := public.resolve_church_id(p_church_id);

  -- THE AUTHORITY CHECK. Ordination is conferred by the conference, not by a local
  -- pastor, so this refuses every role that is not a denominational officer (or COA
  -- staff, or the bishop of this church's own organisation). A 'pastor' calling this
  -- gets this message and nothing else.
  IF NOT public.can_issue_ordination(v_church) THEN
    RAISE EXCEPTION 'only a bishop or conference officer may issue a credential';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_holder_user_id) THEN
    RAISE EXCEPTION 'holder not found';
  END IF;

  IF v_church IS NOT NULL THEN
    SELECT public.church_tenant_id(v_church) INTO v_tenant;
    IF v_tenant IS NULL THEN
      RAISE EXCEPTION 'church % has no tenancy record', v_church;
    END IF;
  ELSE
    IF p_church_id IS NOT NULL THEN
      RAISE EXCEPTION 'church % not found', p_church_id;
    END IF;
    -- Conference-wide: it belongs to no church, and that is correct.
    v_tenant := NULL;
  END IF;

  -- Already active in this office. The partial unique index would catch it too, but
  -- a nameable error tells the bishop they must REVOKE the old one first rather than
  -- simply failing.
  IF EXISTS (
    SELECT 1 FROM public.ministerial_credentials
     WHERE holder_user_id = p_holder_user_id
       AND credential_type = p_credential_type
       AND ministry_role = p_ministry_role
       AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'this person already holds an active % credential as %',
      p_credential_type, p_ministry_role;
  END IF;

  -- The issuing authority defaults to the parent organisation's name (falling back
  -- to the church's own name), so a certificate never has a blank "issued by".
  v_authority := NULLIF(btrim(COALESCE(p_issuing_authority, '')), '');
  IF v_authority IS NULL AND v_church IS NOT NULL THEN
    SELECT COALESCE(o.name, t.name)
      INTO v_authority
      FROM public.churches c
      LEFT JOIN public.organizations o ON o.id = c.organization_id
      LEFT JOIN public.tenants t ON t.id::text = public.church_tenant_id(c.id)
     WHERE c.id = v_church;
  END IF;
  IF v_authority IS NULL OR v_authority = '' THEN
    -- A conference-wide ordination with nothing else to name: record who conferred it.
    SELECT COALESCE(full_name, 'The Conference') INTO v_authority
      FROM public.profiles WHERE id = v_uid;
  END IF;

  -- A blank number is minted here; a number typed in by hand is kept but upper-cased
  -- so "ord/2026/0042" and "ORD/2026/0042" cannot both exist.
  v_number := NULLIF(btrim(COALESCE(p_credential_number, '')), '');
  IF v_number IS NULL THEN
    v_number := public.next_ordination_credential_number();
  ELSE
    v_number := upper(v_number);
  END IF;

  IF p_expires_on IS NULL THEN
    -- Ordination is normally for life. Only a conference that set a validity in
    -- platform_settings gets an automatic expiry.
    SELECT value INTO v_months
      FROM public.platform_settings
     WHERE key = 'ministerial_credential_validity_months';
    IF v_months IS NOT NULL AND v_months ~ '^\d+$' AND v_months::INT > 0 THEN
      v_expires := (COALESCE(p_issued_on, CURRENT_DATE)::timestamp
                    + (v_months || ' months')::interval)::date;
    END IF;
  ELSE
    v_expires := p_expires_on;
  END IF;

  INSERT INTO public.ministerial_credentials
    (holder_user_id, credential_type, ministry_role, credential_number, status,
     issuing_authority, church_id, tenant_id, issued_on, expires_on,
     granted_by, notes)
  VALUES
    (p_holder_user_id, p_credential_type, p_ministry_role, v_number, 'active',
     v_authority, v_church, v_tenant, COALESCE(p_issued_on, CURRENT_DATE),
     v_expires, v_uid, p_notes)
  RETURNING * INTO v_row;

  PERFORM public.append_credential_event(
    v_row.id, 'granted', NULL, 'active', NULL,
    jsonb_build_object('credential_number', v_number,
                       'credential_type', p_credential_type,
                       'ministry_role', p_ministry_role,
                       'church_id', v_church));

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.grant_ministerial_credential(
  uuid, text, text, uuid, text, date, date, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_ministerial_credential(
  uuid, text, text, uuid, text, date, date, text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.renew_ministerial_credential(
  p_credential_id UUID,
  p_expires_on DATE,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.ministerial_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ministerial_credentials;
  v_prev TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_expires_on IS NULL THEN
    RAISE EXCEPTION 'a new expiry date is required';
  END IF;

  SELECT * INTO v_row
    FROM public.ministerial_credentials
   WHERE id = p_credential_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credential not found'; END IF;

  IF NOT public.can_issue_ordination(v_row.church_id) THEN
    RAISE EXCEPTION 'only a bishop or conference officer may renew a credential';
  END IF;

  -- Renewal cannot launder a revocation: a withdrawal must be answered for, either
  -- by granting a NEW credential (which keeps both rows) or by reinstating it.
  IF v_row.status = 'revoked' THEN
    RAISE EXCEPTION 'a revoked credential cannot be renewed; grant a new one instead';
  END IF;

  v_prev := v_row.status;
  UPDATE public.ministerial_credentials
     SET status = 'active',
         expires_on = p_expires_on,
         notes = COALESCE(p_notes, notes),
         updated_at = now()
   WHERE id = p_credential_id
  RETURNING * INTO v_row;

  PERFORM public.append_credential_event(
    v_row.id, 'renewed', v_prev, 'active', p_notes,
    jsonb_build_object('expires_on', p_expires_on,
                       'credential_number', v_row.credential_number));

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.renew_ministerial_credential(uuid, date, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_ministerial_credential(uuid, date, text)
  TO authenticated, service_role;

-- Revoke OR suspend OR record an expiry.
--
-- The name is `revoke_ministerial_credential` because revocation is the act that
-- matters; `p_status` distinguishes it from a suspension (a temporary withdrawal)
-- and from a recorded expiry. All three share one shape: the row survives, the
-- reason is mandatory, and an event is appended.
CREATE OR REPLACE FUNCTION public.revoke_ministerial_credential(
  p_credential_id UUID,
  p_status TEXT DEFAULT 'revoked',
  p_reason TEXT DEFAULT NULL
)
RETURNS public.ministerial_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ministerial_credentials;
  v_prev TEXT;
  v_event TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_status NOT IN ('revoked', 'suspended', 'expired') THEN
    RAISE EXCEPTION 'unknown status %', p_status;
  END IF;

  -- A withdrawal with no stated cause tells the holder nothing and tells the next
  -- church nothing. It is not a record.
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'a reason is required';
  END IF;

  SELECT * INTO v_row
    FROM public.ministerial_credentials
   WHERE id = p_credential_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credential not found'; END IF;

  -- The SAME authority that granted it can take it away. A local pastor can neither
  -- confer nor withdraw an ordination, even from someone they appointed.
  IF NOT public.can_issue_ordination(v_row.church_id) THEN
    RAISE EXCEPTION 'only a bishop or conference officer may revoke a credential';
  END IF;

  IF v_row.status = p_status THEN
    RAISE EXCEPTION 'this credential is already %', p_status;
  END IF;

  v_prev := v_row.status;
  v_event := CASE p_status
               WHEN 'revoked'  THEN 'revoked'
               WHEN 'suspended' THEN 'suspended'
               ELSE 'expired'
             END;

  -- NOTE what is deliberately NOT touched here: the holder's `church_officers` row.
  -- A revoked ordination does not remove somebody from their church's elders board -
  -- the church ends its own appointment, through its own authority. That separation
  -- is the entire reason there are two registers.
  UPDATE public.ministerial_credentials
     SET status = p_status,
         revoked_at = now(),
         revoked_by = auth.uid(),
         revocation_reason = btrim(p_reason),
         updated_at = now()
   WHERE id = p_credential_id
  RETURNING * INTO v_row;

  PERFORM public.append_credential_event(
    v_row.id, v_event, v_prev, p_status, btrim(p_reason),
    jsonb_build_object('credential_number', v_row.credential_number,
                       'holder_user_id', v_row.holder_user_id,
                       'served_at_church', v_row.church_id,
                       'served_since', v_row.issued_on));

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.revoke_ministerial_credential(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_ministerial_credential(uuid, text, text)
  TO authenticated, service_role;

-- Lift a SUSPENDED credential without minting a new number, keeping the same
-- credential_number the holder has been quoting. A REVOCATION is final: restoring
-- one means granting a NEW credential (which keeps both rows), never quietly
-- un-revoking this one.
CREATE OR REPLACE FUNCTION public.reinstate_ministerial_credential(
  p_credential_id UUID,
  p_reason TEXT
)
RETURNS public.ministerial_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ministerial_credentials;
  v_prev TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'a reason is required';
  END IF;

  SELECT * INTO v_row
    FROM public.ministerial_credentials
   WHERE id = p_credential_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credential not found'; END IF;

  IF v_row.status <> 'suspended' THEN
    RAISE EXCEPTION 'only a suspended credential can be reinstated (this one is %)',
      v_row.status;
  END IF;

  IF NOT public.can_issue_ordination(v_row.church_id) THEN
    RAISE EXCEPTION 'only a bishop or conference officer may reinstate a credential';
  END IF;

  v_prev := v_row.status;
  UPDATE public.ministerial_credentials
     SET status = 'active',
         revoked_at = NULL,
         revoked_by = NULL,
         revocation_reason = NULL,
         updated_at = now()
   WHERE id = p_credential_id
  RETURNING * INTO v_row;

  PERFORM public.append_credential_event(
    v_row.id, 'reinstated', v_prev, 'active', btrim(p_reason),
    jsonb_build_object('credential_number', v_row.credential_number));

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.reinstate_ministerial_credential(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reinstate_ministerial_credential(uuid, text)
  TO authenticated, service_role;

-- ===========================================================================
-- 10. (C) BRANCH LICENSING RPCs
-- ===========================================================================
-- A branch APPLIES; its parent organisation GRANTS. Both directions are separate
-- RPCs so neither side can act as the other.

CREATE OR REPLACE FUNCTION public.apply_for_branch_license(
  p_church_id UUID,
  p_application_reference TEXT DEFAULT NULL,
  p_requirements JSONB DEFAULT '{}'::jsonb
)
RETURNS public.branch_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_org UUID;
  v_ref TEXT;
  v_church UUID;
  v_row public.branch_licenses;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_requirements IS NULL OR jsonb_typeof(p_requirements) <> 'object' THEN
    RAISE EXCEPTION 'the requirements checklist must be an object';
  END IF;

  -- The client sends the TENANCY id; the table stores `churches.id`.
  v_church := public.resolve_church_id(p_church_id);
  IF v_church IS NULL THEN
    RAISE EXCEPTION 'church % not found', p_church_id;
  END IF;

  -- The caller needs leadership of the BRANCH - the same authority that could write
  -- its officers roll - or COA staff.
  IF NOT public.can_manage_church_officers(v_church) THEN
    RAISE EXCEPTION 'only church leadership may apply for a branch licence';
  END IF;

  -- A branch of nothing cannot be licensed by nobody. If the church is not linked to
  -- an organisation, there is no body that could ever grant this.
  SELECT c.organization_id INTO v_org
    FROM public.churches c
   WHERE c.id = v_church;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'link this church to its organisation before applying for a licence';
  END IF;

  -- One application in flight per branch. The partial unique index would reject it
  -- too; this says WHICH reference is already open.
  SELECT application_reference INTO v_ref
    FROM public.branch_licenses
   WHERE church_id = v_church
     AND status IN ('application_submitted', 'under_review')
   LIMIT 1;
  IF v_ref IS NOT NULL THEN
    RAISE EXCEPTION 'an application (%s) is already open for this branch', v_ref;
  END IF;

  v_ref := NULLIF(btrim(COALESCE(p_application_reference, '')), '');
  IF v_ref IS NULL THEN
    v_ref := public.next_branch_license_number(v_org, 'application');
  ELSE
    v_ref := upper(v_ref);
  END IF;

  INSERT INTO public.branch_licenses
    (church_id, organization_id, status, application_reference, requirements,
     submitted_by, submitted_at)
  VALUES
    (v_church, v_org, 'application_submitted', v_ref,
     COALESCE(p_requirements, '{}'::jsonb), v_uid, now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.apply_for_branch_license(uuid, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_for_branch_license(uuid, text, jsonb)
  TO authenticated, service_role;

-- Move an application into review. Separate from the DECISION on purpose: in a real
-- conference the secretary RECEIVES the application and the bishop DECIDES it, and
-- they are usually different people. Folding the two together would force the bishop
-- to be the intake clerk too, and would erase the fact that anybody read it at all.
CREATE OR REPLACE FUNCTION public.review_branch_license(p_license_id UUID)
RETURNS public.branch_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.branch_licenses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_row
    FROM public.branch_licenses
   WHERE id = p_license_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'licence application not found'; END IF;

  IF NOT public.is_branch_license_authority(v_row.organization_id) THEN
    RAISE EXCEPTION 'only an officer of the parent organisation may review this application';
  END IF;

  IF v_row.status <> 'application_submitted' THEN
    RAISE EXCEPTION 'this application is %', v_row.status;
  END IF;

  UPDATE public.branch_licenses
     SET status = 'under_review',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   WHERE id = p_license_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.review_branch_license(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_branch_license(uuid)
  TO authenticated, service_role;

-- Grant or refuse. `p_decision`:
--   'licensed' -> status 'licensed', licence number minted, validity window set
--   'rejected' -> back to 'unlicensed', with the reason kept in decision_notes
--
-- 'unlicensed' is a real end state here rather than a missing row: "we looked at it
-- and said no" IS an outcome the branch needs to read, and the reason for it is the
-- part it will be asked about at the next conference.
CREATE OR REPLACE FUNCTION public.decide_branch_license(
  p_license_id UUID,
  p_decision TEXT,
  p_notes TEXT DEFAULT NULL,
  p_expires_on DATE DEFAULT NULL
)
RETURNS public.branch_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row public.branch_licenses;
  v_outstanding TEXT;
  v_number TEXT;
  v_months TEXT;
  v_lead TEXT;
  v_issued DATE := CURRENT_DATE;
  v_expires DATE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_decision NOT IN ('licensed', 'rejected') THEN
    RAISE EXCEPTION 'unknown decision %', p_decision;
  END IF;

  SELECT * INTO v_row
    FROM public.branch_licenses
   WHERE id = p_license_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'licence application not found'; END IF;

  -- The parent organisation decides. A branch cannot licence itself, and neither can
  -- a branch pastor sitting in another branch of the same organisation - which is
  -- exactly what `is_org_owner` would have allowed.
  IF NOT public.is_branch_license_authority(v_row.organization_id) THEN
    RAISE EXCEPTION 'only an officer of the parent organisation may decide this application';
  END IF;

  IF v_row.status NOT IN ('application_submitted', 'under_review') THEN
    RAISE EXCEPTION 'this application is %', v_row.status;
  END IF;

  IF p_decision = 'rejected' THEN
    IF p_notes IS NULL OR length(btrim(p_notes)) < 3 THEN
      RAISE EXCEPTION 'a reason is required when refusing a licence';
    END IF;
    UPDATE public.branch_licenses
       SET status = 'unlicensed',
           reviewed_by = v_uid,
           reviewed_at = now(),
           decision_notes = btrim(p_notes),
           updated_at = now()
     WHERE id = p_license_id
    RETURNING * INTO v_row;
    RETURN v_row;
  END IF;

  -- The checklist is the point of a licence. An item explicitly ticked FALSE blocks
  -- the grant - otherwise the checklist would be decoration. Absent keys are not
  -- required, so a conference only lists what it actually assesses.
  SELECT string_agg(e.key, ', ' ORDER BY e.key) INTO v_outstanding
    FROM jsonb_each_text(COALESCE(v_row.requirements, '{}'::jsonb)) AS e(key, value)
   WHERE lower(btrim(e.value)) IN ('false', 'no', '0');
  IF v_outstanding IS NOT NULL THEN
    RAISE EXCEPTION 'the branch has not met these requirements: %', v_outstanding;
  END IF;

  SELECT value INTO v_months
    FROM public.platform_settings WHERE key = 'branch_license_validity_months';
  SELECT value INTO v_lead
    FROM public.platform_settings WHERE key = 'branch_license_renewal_lead_days';

  v_expires := COALESCE(
    p_expires_on,
    (v_issued::timestamp
     + (GREATEST(1, COALESCE(
         CASE WHEN v_months ~ '^\d+$' THEN v_months::INT END, 12))
       || ' months')::interval)::date);
  IF v_expires < v_issued THEN
    RAISE EXCEPTION 'a licence cannot expire before it is issued';
  END IF;

  -- Keep the SAME number across re-grants of the same application; mint one only the
  -- first time. A licence number that changed on every decision would be useless to
  -- quote.
  v_number := v_row.license_number;
  IF v_number IS NULL OR btrim(v_number) = '' THEN
    v_number := public.next_branch_license_number(v_row.organization_id, 'license');
  END IF;

  UPDATE public.branch_licenses
     SET status = 'licensed',
         license_number = v_number,
         issued_at = now(),
         expires_at = v_expires,
         renewal_due_at = (v_expires - GREATEST(0, COALESCE(
             CASE WHEN v_lead ~ '^\d+$' THEN v_lead::INT END, 30)))::date,
         revoked_at = NULL,
         revoked_by = NULL,
         revocation_reason = NULL,
         suspended_at = NULL,
         suspension_reason = NULL,
         reviewed_by = v_uid,
         reviewed_at = now(),
         decision_notes = COALESCE(p_notes, decision_notes),
         updated_at = now()
   WHERE id = p_license_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.decide_branch_license(uuid, text, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_branch_license(uuid, text, text, date)
  TO authenticated, service_role;

-- Renew a licence: SAME number, fresh window. Real licences renew - they do not mint
-- a new identity every year - so the branch's certificate number stays quotable and
-- the conference can see it is the same branch it licensed last year.
--
-- NOTE the guard is `status = 'licensed'`, not "not expired". A licence whose date
-- has simply passed is still stored as 'licensed' (see the header: expiry is derived,
-- never written by a trigger), so this is exactly the function a lapsed branch needs
-- and a lapsed branch is never permanently stuck.
CREATE OR REPLACE FUNCTION public.renew_branch_license(
  p_license_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.branch_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.branch_licenses;
  v_months TEXT;
  v_lead TEXT;
  v_issued DATE := CURRENT_DATE;
  v_expires DATE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_row
    FROM public.branch_licenses
   WHERE id = p_license_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'licence not found'; END IF;

  IF NOT public.is_branch_license_authority(v_row.organization_id) THEN
    RAISE EXCEPTION 'only an officer of the parent organisation may renew a licence';
  END IF;

  IF v_row.status <> 'licensed' THEN
    RAISE EXCEPTION 'only a licensed branch may renew (this one is %)', v_row.status;
  END IF;

  SELECT value INTO v_months
    FROM public.platform_settings WHERE key = 'branch_license_validity_months';
  SELECT value INTO v_lead
    FROM public.platform_settings WHERE key = 'branch_license_renewal_lead_days';

  v_expires := (v_issued::timestamp
                + (GREATEST(1, COALESCE(
                     CASE WHEN v_months ~ '^\d+$' THEN v_months::INT END, 12))
                   || ' months')::interval)::date;

  UPDATE public.branch_licenses
     SET status = 'licensed',
         issued_at = now(),
         expires_at = v_expires,
         renewal_due_at = (v_expires - GREATEST(0, COALESCE(
             CASE WHEN v_lead ~ '^\d+$' THEN v_lead::INT END, 30)))::date,
         decision_notes = COALESCE(p_notes, decision_notes),
         updated_at = now()
   WHERE id = p_license_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.renew_branch_license(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_branch_license(uuid, text)
  TO authenticated, service_role;

-- Suspend, revoke, or reinstate an EXISTING licence. Needed so those two states are
-- reached through an audited, permission-checked transition rather than a raw client
-- UPDATE - which this register does not permit at all.
--
-- Reinstating a suspension deliberately KEEPS issued_at and expires_at: a suspension
-- is a temporary withdrawal, not a fresh grant, and the branch should not lose the
-- months it has already served this term. A genuine renewal (a new term) is
-- `renew_branch_license`.
CREATE OR REPLACE FUNCTION public.set_branch_license_status(
  p_license_id UUID,
  p_status TEXT,
  p_reason TEXT
)
RETURNS public.branch_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.branch_licenses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_status NOT IN ('suspended', 'revoked', 'licensed') THEN
    RAISE EXCEPTION 'unknown status %', p_status;
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'a reason is required';
  END IF;

  SELECT * INTO v_row
    FROM public.branch_licenses
   WHERE id = p_license_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'licence not found'; END IF;

  IF NOT public.is_branch_license_authority(v_row.organization_id) THEN
    RAISE EXCEPTION 'only an officer of the parent organisation may change this licence';
  END IF;

  IF p_status IN ('suspended', 'revoked')
     AND v_row.status NOT IN ('licensed', 'suspended') THEN
    -- Nothing can be suspended or revoked that was never issued.
    RAISE EXCEPTION 'this branch does not hold a live licence (it is %)', v_row.status;
  END IF;

  IF p_status = 'licensed' AND v_row.status <> 'suspended' THEN
    RAISE EXCEPTION 'only a suspended licence can be reinstated (this one is %)',
      v_row.status;
  END IF;

  UPDATE public.branch_licenses
     SET status = p_status,
         suspended_at = CASE WHEN p_status = 'suspended' THEN now() ELSE NULL END,
         suspension_reason = CASE WHEN p_status = 'suspended'
                                  THEN btrim(p_reason) ELSE NULL END,
         revoked_at = CASE WHEN p_status = 'revoked' THEN now() ELSE NULL END,
         revoked_by = CASE WHEN p_status = 'revoked' THEN auth.uid() ELSE NULL END,
         revocation_reason = CASE WHEN p_status = 'revoked'
                                  THEN btrim(p_reason) ELSE NULL END,
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         decision_notes = btrim(p_reason),
         updated_at = now()
   WHERE id = p_license_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_branch_license_status(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_branch_license_status(uuid, text, text)
  TO authenticated, service_role;

-- ===========================================================================
-- 11. AUDIT
-- ===========================================================================
-- The tenant-visible activity trail (20261247) records every insert and update of
-- these three registers, whoever performed it - a client, an RPC, an admin tool or a
-- psql session. `ministerial_credential_events` is deliberately NOT attached: it IS
-- the audit trail for credentials, and an audit of an audit is only noise.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['church_officers', 'ministerial_credentials',
                            'branch_licenses'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_church_audit_%I ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_church_audit_%I
         AFTER INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture()', t, t);
  END LOOP;
END;
$$;

-- ===========================================================================
-- 12. VERIFICATION
-- ===========================================================================
-- Refuse to ship a governance register that cannot be governed. Every predicate is
-- folded into ONE union so a failure names EVERY problem at once instead of one per
-- re-run.
DO $$
DECLARE
  v_fail TEXT;
BEGIN
  SELECT string_agg(check_name, ', ' ORDER BY check_name) INTO v_fail
  FROM (
    -- The four registers exist.
    SELECT 'tables_missing' AS check_name
    WHERE (SELECT count(*) FROM (VALUES
             ('church_officers'), ('ministerial_credentials'),
             ('ministerial_credential_events'), ('branch_licenses')) AS t(name)
           WHERE to_regclass('public.' || name) IS NULL) <> 0

    -- ... and RLS is on for all four.
    UNION ALL
    SELECT 'rls_disabled'
    WHERE (SELECT count(*) FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname IN ('church_officers', 'ministerial_credentials',
                                'ministerial_credential_events', 'branch_licenses')
              AND c.relrowsecurity) <> 4

    -- `anon` holds nothing.
    UNION ALL
    SELECT 'anon_has_table_grant'
    WHERE EXISTS (
      SELECT 1 FROM information_schema.role_table_grants
       WHERE table_schema = 'public'
         AND table_name IN ('church_officers', 'ministerial_credentials',
                           'ministerial_credential_events', 'branch_licenses')
         AND grantee = 'anon')

    -- No client write path: no write policy on any of the four.
    UNION ALL
    SELECT 'client_write_policy_exists'
    WHERE EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename IN ('church_officers', 'ministerial_credentials',
                           'ministerial_credential_events', 'branch_licenses')
         AND cmd IN ('INSERT', 'UPDATE', 'DELETE'))

    -- No blanket policy of any kind.
    UNION ALL
    SELECT 'blanket_true_policy'
    WHERE EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename IN ('church_officers', 'ministerial_credentials',
                           'ministerial_credential_events', 'branch_licenses')
         AND (COALESCE(qual, '') LIKE '%true%' OR COALESCE(with_check, '') LIKE '%true%'))

    -- `authenticated` may not write directly. The privilege is REVOKED, not merely
    -- unused, because Postgres checks table grants BEFORE RLS.
    UNION ALL
    SELECT 'authenticated_can_write_directly'
    WHERE EXISTS (
      SELECT 1 FROM information_schema.role_table_grants
       WHERE table_schema = 'public'
         AND table_name IN ('church_officers', 'ministerial_credentials',
                           'ministerial_credential_events', 'branch_licenses')
         AND grantee = 'authenticated'
         AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE'))

    -- Every RPC and every private helper is closed to `anon`.
    UNION ALL
    SELECT 'anon_can_execute_rpc'
    WHERE has_function_privilege('anon', 'public.appoint_officer(uuid, uuid, text, date, date, boolean, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.end_officer_appointment(uuid, text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.grant_ministerial_credential(uuid, text, text, uuid, text, date, date, text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.renew_ministerial_credential(uuid, date, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.revoke_ministerial_credential(uuid, text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.reinstate_ministerial_credential(uuid, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.apply_for_branch_license(uuid, text, jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.review_branch_license(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.decide_branch_license(uuid, text, text, date)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.renew_branch_license(uuid, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_branch_license_status(uuid, text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.append_credential_event(uuid, text, text, text, text, jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.next_ordination_credential_number()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.next_branch_license_number(uuid, text)', 'EXECUTE')

    -- SECURITY DEFINER without a pinned search_path is the one mistake that makes
    -- all of the above meaningless.
    UNION ALL
    SELECT 'secdef_without_search_path'
    WHERE EXISTS (
      SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname IN ('resolve_church_id', 'church_tenant_id',
                            'can_manage_church_officers',
                            'can_view_church_officers', 'can_issue_ordination',
                            'can_view_ordinations', 'is_branch_license_authority',
                            'can_view_branch_license', 'next_ordination_credential_number',
                            'next_branch_license_number', 'append_credential_event',
                            'appoint_officer', 'end_officer_appointment',
                            'grant_ministerial_credential', 'renew_ministerial_credential',
                            'revoke_ministerial_credential', 'reinstate_ministerial_credential',
                            'apply_for_branch_license', 'review_branch_license',
                            'decide_branch_license', 'renew_branch_license',
                            'set_branch_license_status',
                            'touch_church_governance_updated_at')
         AND p.prosecdef
         AND COALESCE(array_to_string(p.proconfig, ','), '') NOT LIKE '%search_path%')

    -- The audit trail must actually be attached, or "it must write an audit row" is
    -- just a comment.
    UNION ALL
    SELECT 'audit_trigger_missing'
    WHERE (SELECT count(*) FROM pg_trigger
            WHERE tgname IN ('trg_church_audit_church_officers',
                             'trg_church_audit_ministerial_credentials',
                             'trg_church_audit_branch_licenses')
              AND NOT tgisinternal) <> 3

    -- ... and so must updated_at, or the audit log records unchanged timestamps.
    UNION ALL
    SELECT 'updated_at_trigger_missing'
    WHERE (SELECT count(*) FROM pg_trigger
            WHERE tgname IN ('trg_touch_church_officers_updated_at',
                             'trg_touch_ministerial_credentials_updated_at',
                             'trg_touch_branch_licenses_updated_at')
              AND NOT tgisinternal) <> 3
  ) bad;

  IF v_fail IS NOT NULL THEN
    RAISE EXCEPTION 'governance registers failed verification: %', v_fail;
  END IF;
END;
$$;

-- The single result set `supabase db query --file` prints: one row per check, so
-- the whole posture is visible in one paste.
SELECT check_name, passed, detail
FROM (
  SELECT 'tables_created' AS check_name, true AS passed,
         'church_officers, ministerial_credentials, ministerial_credential_events, '
         || 'branch_licenses' AS detail
  UNION ALL
  SELECT 'rls_enabled_on_all', true,
         (SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname IN ('church_officers', 'ministerial_credentials',
                               'ministerial_credential_events', 'branch_licenses')
             AND c.relrowsecurity)
  UNION ALL
  SELECT 'anon_holds_no_grant',
         NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
                      WHERE table_schema = 'public'
                        AND table_name IN ('church_officers', 'ministerial_credentials',
                                          'ministerial_credential_events', 'branch_licenses')
                        AND grantee = 'anon'),
         'no table grant for anon'
  UNION ALL
  SELECT 'rpc_only_writes',
         NOT EXISTS (SELECT 1 FROM pg_policies
                      WHERE schemaname = 'public'
                        AND tablename IN ('church_officers', 'ministerial_credentials',
                                          'ministerial_credential_events', 'branch_licenses')
                        AND cmd IN ('INSERT', 'UPDATE', 'DELETE')),
         'no INSERT/UPDATE/DELETE policy on any register'
  UNION ALL
  SELECT 'append_only_credential_events',
         NOT EXISTS (SELECT 1 FROM pg_policies
                      WHERE schemaname = 'public'
                        AND tablename = 'ministerial_credential_events'
                        AND cmd IN ('INSERT', 'UPDATE', 'DELETE')),
         'the credential trail is appended to only by the RPCs'
  UNION ALL
  SELECT 'functions_created',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname IN ('resolve_church_id', 'church_tenant_id',
                               'can_manage_church_officers',
                               'can_view_church_officers', 'can_issue_ordination',
                               'can_view_ordinations', 'is_branch_license_authority',
                               'can_view_branch_license', 'next_ordination_credential_number',
                               'next_branch_license_number', 'append_credential_event',
                               'appoint_officer', 'end_officer_appointment',
                               'grant_ministerial_credential', 'renew_ministerial_credential',
                               'revoke_ministerial_credential', 'reinstate_ministerial_credential',
                               'apply_for_branch_license', 'review_branch_license',
                               'decide_branch_license', 'renew_branch_license',
                               'set_branch_license_status',
                               'touch_church_governance_updated_at')) = 23,
         '23 functions: 8 permission helpers, 1 updated_at trigger, 2 number '
         || 'generators, 1 private event writer, 11 RPCs'
  UNION ALL
  SELECT 'audit_triggers',
         (SELECT count(*) FROM pg_trigger
           WHERE tgname IN ('trg_church_audit_church_officers',
                            'trg_church_audit_ministerial_credentials',
                            'trg_church_audit_branch_licenses')
             AND NOT tgisinternal) = 3,
         'church_officers, ministerial_credentials, branch_licenses'
  UNION ALL
  SELECT 'ordination_gate',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'can_issue_ordination'),
         'can_issue_ordination(uuid): bishop / apostle / prophet / conference '
         || 'secretary or treasurer / this org''s bishop_id / COA staff'
  UNION ALL
  SELECT 'branch_licence_gate',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'is_branch_license_authority'),
         'is_branch_license_authority(uuid): this org''s bishop / secretary / '
         || 'treasurer, or COA staff - deliberately NOT is_org_owner'
  UNION ALL
  SELECT 'remote_config_keys',
         (SELECT count(*) FROM public.platform_settings
           WHERE key IN ('branch_license_validity_months',
                          'branch_license_renewal_lead_days',
                          'ministerial_credential_validity_months')) = 3,
         'licence validity is a business value, not a constant in code'
) checks;