-- ============================================================================
-- 20261132_tenant_owner_tier.sql
-- Who is allowed to pay for (and be reminded about) a tenancy.
--
-- MODEL (per product owner):
--   * ONLY the tenant OWNER TIER ever sees a paywall / payment reminder.
--   * Owner-tier users are NEVER charged for themselves — their single purpose
--     is to make sure their tenancy is paid up.
--   * Owner tier = pastor, bishop, apostle, prophet, general_secretary,
--     general_treasurer, treasurer (local church treasurer included)
--     PLUS custom delegates added by the pastor (for their church) or by the
--     bishop (for their organisation).
--   * Every other member/leader (assistant pastor, assistant bishop, assistant,
--     leader, department leader, usher, driver, rider, vendor, merchant, writer,
--     member, ...) must NEVER see a paywall and never pay to join.
--   * Members only ever pay for: quiz store kits, and Church Coins (CC) —
--     e.g. leasing the quiz engine as an individual.
-- ============================================================================

-- ── 1. Owner-tier role test ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_owner_tier_role(p_role text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(coalesce(p_role, '')) IN (
    'pastor',
    'bishop',
    'apostle',
    'prophet',
    'general_secretary',
    'general_treasurer',
    'treasurer'
  );
$$;

-- ── 1b. MISSING COLUMN FIX ──────────────────────────────────────────────────
-- `bookshops.onboarding_fee_paid` exists but `churches` NEVER had the column,
-- even though the COA approval / paywall flows reference it. Add it so the
-- church fee lifecycle can actually be recorded.
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS onboarding_fee_paid boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_fee_paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS onboarding_fee_ref text;

-- ── 2. Custom delegates ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenant_owner_delegates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   text NOT NULL,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  scope       text NOT NULL DEFAULT 'church',   -- church | organisation
  note        text,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_owner_delegates_user
  ON public.tenant_owner_delegates (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_owner_delegates_tenant
  ON public.tenant_owner_delegates (tenant_id, is_active);

ALTER TABLE public.tenant_owner_delegates ENABLE ROW LEVEL SECURITY;

-- You can see your own delegate row, plus rows for a tenancy you own.
-- (Policy declared after `is_tenant_owner` is defined, further down.)

-- ── 3. Am I an owner of this tenancy? ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_tenant_owner(p_tenant_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND (
        (p.tenant_id = p_tenant_id AND public.is_owner_tier_role(p.role))
        OR EXISTS (
          SELECT 1 FROM public.tenant_owner_delegates d
          WHERE d.user_id = p.id
            AND d.tenant_id = p_tenant_id
            AND d.is_active
        )
      )
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_tenant_owner(text) FROM anon;

-- Am I an owner of the tenancy I belong to? (the common client check)
CREATE OR REPLACE FUNCTION public.am_i_tenant_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_tenant_owner(
    (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
  );
$$;

REVOKE EXECUTE ON FUNCTION public.am_i_tenant_owner() FROM anon;

-- Delegate rows are readable by their owner, by any owner of that tenancy, and
-- by platform staff. Writes go only through the RPCs below.
DROP POLICY IF EXISTS "owner_delegates_read" ON public.tenant_owner_delegates;
CREATE POLICY "owner_delegates_read"
  ON public.tenant_owner_delegates FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_tenant_owner(tenant_id)
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- ── 4. Grant / revoke a custom owner ────────────────────────────────────────
-- A PASTOR may add owners for their own church/branch.
-- A BISHOP (or apostle/prophet/general secretary) may add owners for any
-- church inside their ORGANISATION.
CREATE OR REPLACE FUNCTION public.grant_tenant_owner(
  p_user_id uuid,
  p_note    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_my_role    text;
  v_my_tenant  text;
  v_my_org     uuid;
  v_target_tid text;
  v_target_org uuid;
  v_scope      text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT role, tenant_id INTO v_my_role, v_my_tenant
    FROM public.profiles WHERE id = v_uid;

  SELECT tenant_id INTO v_target_tid FROM public.profiles WHERE id = p_user_id;
  IF v_target_tid IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'target_has_no_tenant');
  END IF;

  IF v_target_tid = v_my_tenant THEN
    -- Same church: the pastor of that church (owner-tier) may grant.
    IF NOT public.is_tenant_owner(v_target_tid) THEN
      RETURN jsonb_build_object('granted', false, 'reason', 'not_owner_of_this_church');
    END IF;
    v_scope := 'church';
  ELSE
    -- Different church: only an organisation-level owner (bishop & co) of the
    -- ORGANISATION that contains the target church may grant.
    IF lower(coalesce(v_my_role, '')) NOT IN
       ('bishop', 'apostle', 'prophet', 'general_secretary') THEN
      RETURN jsonb_build_object('granted', false, 'reason', 'org_owner_required');
    END IF;

    SELECT organization_id INTO v_my_org
      FROM public.churches WHERE tenant_id = v_my_tenant LIMIT 1;
    SELECT organization_id INTO v_target_org
      FROM public.churches WHERE tenant_id = v_target_tid LIMIT 1;

    IF v_my_org IS NULL OR v_target_org IS NULL OR v_my_org <> v_target_org THEN
      RETURN jsonb_build_object('granted', false, 'reason', 'different_organisation');
    END IF;
    v_scope := 'organisation';
  END IF;

  INSERT INTO public.tenant_owner_delegates
    (tenant_id, user_id, granted_by, scope, note)
  VALUES (v_target_tid, p_user_id, v_uid, v_scope, p_note)
  ON CONFLICT (tenant_id, user_id)
  DO UPDATE SET is_active = true, granted_by = v_uid, scope = excluded.scope,
                note = excluded.note;

  RETURN jsonb_build_object('granted', true, 'tenant_id', v_target_tid,
                            'scope', v_scope);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.grant_tenant_owner(uuid, text) FROM anon;

CREATE OR REPLACE FUNCTION public.revoke_tenant_owner(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tid text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = p_user_id;
  IF v_tid IS NULL THEN
    RETURN jsonb_build_object('revoked', false, 'reason', 'no_tenant');
  END IF;

  IF NOT public.is_tenant_owner(v_tid) THEN
    RETURN jsonb_build_object('revoked', false, 'reason', 'not_owner');
  END IF;

  UPDATE public.tenant_owner_delegates
     SET is_active = false
   WHERE user_id = p_user_id AND tenant_id = v_tid;

  RETURN jsonb_build_object('revoked', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.revoke_tenant_owner(uuid) FROM anon;

-- ── 5. Who should be reminded to pay? (COA alerting + reminders) ────────────
-- Active tenancies that are in trial/near expiry, with the owner-tier people
-- who must be notified. Used by the COA dashboard and the trial cron.
CREATE OR REPLACE FUNCTION public.get_tenancy_payment_reminders(p_days int DEFAULT 7)
RETURNS TABLE (
  tenant_id      text,
  church_name    text,
  subscription_ends_at timestamptz,
  days_left      int,
  onboarding_fee_paid boolean,
  owners         jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.tenant_id::text,
    c.name,
    c.subscription_ends_at,
    GREATEST(0, EXTRACT(DAY FROM (c.subscription_ends_at - now()))::int),
    COALESCE(c.onboarding_fee_paid, false),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id', p.id, 'name', p.full_name, 'role', p.role))
      FROM public.profiles p
      WHERE p.tenant_id = c.tenant_id::text
        AND (
          public.is_owner_tier_role(p.role)
          OR EXISTS (
            SELECT 1 FROM public.tenant_owner_delegates d
            WHERE d.user_id = p.id
              AND d.tenant_id = c.tenant_id::text
              AND d.is_active
          )
        )
    ), '[]'::jsonb)
  FROM public.churches c
  WHERE c.subscription_ends_at IS NOT NULL
    AND c.subscription_ends_at < now() + make_interval(days => GREATEST(p_days, 1))
    AND COALESCE(c.onboarding_fee_paid, false) = false
  ORDER BY c.subscription_ends_at ASC;
$$;

-- Platform-staff only (never expose the full payer list to members).
REVOKE EXECUTE ON FUNCTION public.get_tenancy_payment_reminders(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_tenancy_payment_reminders(int) FROM public;
GRANT EXECUTE ON FUNCTION public.get_tenancy_payment_reminders(int) TO authenticated;
