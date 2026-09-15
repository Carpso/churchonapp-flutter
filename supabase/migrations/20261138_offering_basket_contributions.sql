-- ============================================================================
-- 20261138_offering_basket_contributions.sql
-- Live basket offering contributions.
--
-- WHY: `20261137_offering_baskets.sql` created the basket types + live
-- `offering_sessions`, but nothing ever linked a member's gift to a session, so
-- `offering_sessions.total_amount` / `contribution_count` stayed at 0 and the
-- pastor/bishop `get_basket_summary()` report was always empty. This migration
-- adds the contribution ledger + a SECURITY DEFINER recorder called by the Give
-- flow after a confirmed payment.
--
-- Payments are NOT touched: the existing Lipila collection + settlement path is
-- unchanged. The recorder is a separate, idempotent (by payment_ref) write that
-- only accumulates the live-offering counters.
-- ============================================================================

-- ── 1. Contribution ledger ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.offering_contributions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid NOT NULL REFERENCES public.offering_sessions(id) ON DELETE CASCADE,
  tenant_id    text NOT NULL,
  user_id      uuid,
  amount       numeric NOT NULL DEFAULT 0,
  payment_ref  text NOT NULL,
  method       text DEFAULT 'momo',
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_offering_contributions_ref
  ON public.offering_contributions (payment_ref);
CREATE INDEX IF NOT EXISTS idx_offering_contributions_session
  ON public.offering_contributions (session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offering_contributions_tenant
  ON public.offering_contributions (tenant_id, created_at DESC);

ALTER TABLE public.offering_contributions ENABLE ROW LEVEL SECURITY;

-- Read: your own gifts + the whole tenant ledger for church leadership/staff.
DROP POLICY IF EXISTS "offering_contributions_read" ON public.offering_contributions;
CREATE POLICY "offering_contributions_read"
  ON public.offering_contributions FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );
-- Writes only via the SECURITY DEFINER RPC below.

-- ── 2. Record a contribution into an open session ───────────────────────────
CREATE OR REPLACE FUNCTION public.record_offering_contribution(
  p_session_id  uuid,
  p_amount      numeric,
  p_payment_ref text DEFAULT NULL,
  p_method      text DEFAULT 'momo'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_tid        text;
  v_sess_tenant text;
  v_status     text;
  v_ref        text;
  v_total      numeric;
  v_count      int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = v_uid;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'no tenant'; END IF;

  SELECT tenant_id, status INTO v_sess_tenant, v_status
    FROM public.offering_sessions WHERE id = p_session_id;

  IF v_sess_tenant IS NULL THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'session_not_found');
  END IF;
  IF v_sess_tenant <> v_tid THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;
  IF v_status <> 'open' THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'session_closed');
  END IF;

  -- Idempotent by payment reference so a retry (or offline replay) never
  -- double-counts a gift. A synthetic ref is generated when the caller has none.
  v_ref := COALESCE(
    NULLIF(btrim(COALESCE(p_payment_ref, '')), ''),
    'sess-' || p_session_id::text || '-' || v_uid::text || '-' ||
      (extract(epoch from clock_timestamp()) * 1000)::bigint::text
  );

  INSERT INTO public.offering_contributions
    (session_id, tenant_id, user_id, amount, payment_ref, method)
  VALUES
    (p_session_id, v_tid, v_uid, p_amount, v_ref, COALESCE(p_method, 'momo'))
  ON CONFLICT (payment_ref) DO NOTHING;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'duplicate');
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*)
    INTO v_total, v_count
    FROM public.offering_contributions
   WHERE session_id = p_session_id;

  UPDATE public.offering_sessions
     SET total_amount = v_total,
         contribution_count = v_count
   WHERE id = p_session_id;

  RETURN jsonb_build_object('recorded', true, 'total', v_total, 'count', v_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_offering_contribution(uuid, numeric, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_offering_contribution(uuid, numeric, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.record_offering_contribution(uuid, numeric, text, text) TO authenticated;

-- ── 3. Recompute + freeze totals when a session is closed ───────────────────
CREATE OR REPLACE FUNCTION public.close_offering_session(
  p_session_id uuid,
  p_notes      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_tid   text;
  v_role  text;
  v_total numeric;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT tenant_id, role INTO v_tid, v_role FROM public.profiles WHERE id = v_uid;

  IF NOT (public.is_owner_tier_role(v_role)
          OR lower(coalesce(v_role, '')) IN
             ('superadmin','super_admin','coa_employee','employee',
              'admin','leader','department_leader')) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*)
    INTO v_total, v_count
    FROM public.offering_contributions
   WHERE session_id = p_session_id;

  UPDATE public.offering_sessions
     SET status = 'closed', closed_at = now(),
         notes = COALESCE(p_notes, notes),
         total_amount = v_total,
         contribution_count = v_count
   WHERE id = p_session_id AND tenant_id = v_tid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('closed', false, 'reason', 'not_found');
  END IF;

  RETURN jsonb_build_object('closed', true, 'total', v_total, 'count', v_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_offering_session(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.close_offering_session(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.close_offering_session(uuid, text) TO authenticated;

-- ── 4. Backfill session totals from any pre-existing contributions ──────────
UPDATE public.offering_sessions s
   SET total_amount = COALESCE(c.total, 0),
       contribution_count = COALESCE(c.cnt, 0)
  FROM (
    SELECT session_id, sum(amount) AS total, count(*) AS cnt
      FROM public.offering_contributions
     GROUP BY session_id
  ) c
 WHERE c.session_id = s.id;
