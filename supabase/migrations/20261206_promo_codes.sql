-- ============================================================================
-- 20261206_promo_codes.sql
-- Trackable promo codes awardable to any user by superadmin / COA.
--
-- Distinct from `promo_campaigns` (20260723), which is a marketing-campaign
-- concept. A `promo_code` is a single redeemable code with a typed value.
--
--   kinds: cc | quiz_pass | subscription_discount | event_entry
--
-- All rules (limits, expiry, active) are enforced server-side. Every use is
-- recorded in `promo_code_redemptions` so usage is fully tracked.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.promo_codes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  kind          text NOT NULL DEFAULT 'cc',   -- cc | quiz_pass | subscription_discount | event_entry
  value         numeric NOT NULL DEFAULT 0,
  description   text,
  max_uses      int,                           -- NULL = unlimited
  per_user_limit int NOT NULL DEFAULT 1,
  used_count    int NOT NULL DEFAULT 0,
  expires_at    timestamptz,
  active        boolean NOT NULL DEFAULT true,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.promo_code_redemptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promo_code_id uuid REFERENCES public.promo_codes(id) ON DELETE CASCADE,
  code          text NOT NULL,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  context       jsonb NOT NULL DEFAULT '{}'::jsonb,
  awarded_by    uuid,          -- set when staff-awarded (rather than self-redeemed)
  redeemed_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_redemptions_code
  ON public.promo_code_redemptions (promo_code_id, redeemed_at DESC);
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_user
  ON public.promo_code_redemptions (user_id, redeemed_at DESC);

ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_code_redemptions ENABLE ROW LEVEL SECURITY;

-- Codes themselves are staff-only readable (users redeem via RPC, never by
-- selecting the code list).
DROP POLICY IF EXISTS "promo_codes_staff_read" ON public.promo_codes;
CREATE POLICY "promo_codes_staff_read"
  ON public.promo_codes FOR SELECT TO authenticated
  USING (public.is_platform_staff());

DROP POLICY IF EXISTS "promo_redemptions_own_read" ON public.promo_code_redemptions;
CREATE POLICY "promo_redemptions_own_read"
  ON public.promo_code_redemptions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_staff());

-- Keep updated_at fresh.
CREATE OR REPLACE FUNCTION public.touch_promo_codes_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_promo_codes_updated_at ON public.promo_codes;
CREATE TRIGGER trg_promo_codes_updated_at
  BEFORE UPDATE ON public.promo_codes
  FOR EACH ROW EXECUTE FUNCTION public.touch_promo_codes_updated_at();

-- ── Create (staff) ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_promo_code(
  p_code           text DEFAULT NULL,
  p_kind           text DEFAULT 'cc',
  p_value          numeric DEFAULT 0,
  p_description    text DEFAULT NULL,
  p_max_uses       int DEFAULT NULL,
  p_per_user_limit int DEFAULT 1,
  p_expires_at     timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_code text;
  v_id   uuid;
  v_try  int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;

  IF p_kind NOT IN ('cc', 'quiz_pass', 'subscription_discount', 'event_entry') THEN
    RAISE EXCEPTION 'invalid kind';
  END IF;

  v_code := upper(trim(COALESCE(p_code, '')));
  IF v_code = '' THEN
    -- COA- prefixed, brand-consistent, retried until unique.
    LOOP
      v_try := v_try + 1;
      v_code := 'COA-PROMO-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.promo_codes WHERE code = v_code);
      IF v_try > 10 THEN RAISE EXCEPTION 'could not allocate code'; END IF;
    END LOOP;
  END IF;

  INSERT INTO public.promo_codes
    (code, kind, value, description, max_uses, per_user_limit, expires_at, created_by)
  VALUES
    (v_code, p_kind, COALESCE(p_value, 0), p_description,
     p_max_uses, GREATEST(COALESCE(p_per_user_limit, 1), 1),
     p_expires_at, v_uid)
  RETURNING id INTO v_id;

  -- Register in the generated_codes registry for tracking (best-effort).
  INSERT INTO public.generated_codes (code_type, code_value, country_iso, user_id, metadata)
  VALUES ('promo_code', v_code, 'ZM', v_uid,
          jsonb_build_object('promo_code_id', v_id, 'kind', p_kind))
  ON CONFLICT (code_value) DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'code', v_code);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_promo_code(text, text, numeric, text, int, int, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_promo_code(text, text, numeric, text, int, int, timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION public.create_promo_code(text, text, numeric, text, int, int, timestamptz) TO authenticated;

-- ── Award to a specific user (staff) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_promo_code(
  p_user_id uuid,
  p_code    text,
  p_context jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_promo public.promo_codes%rowtype;
  v_used  int;
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user required'; END IF;

  SELECT * INTO v_promo FROM public.promo_codes
   WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF NOT v_promo.active THEN RETURN jsonb_build_object('ok', false, 'reason', 'inactive'); END IF;
  IF v_promo.expires_at IS NOT NULL AND v_promo.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  SELECT count(*) INTO v_used FROM public.promo_code_redemptions
   WHERE promo_code_id = v_promo.id AND user_id = p_user_id;
  IF v_promo.per_user_limit > 0 AND v_used >= v_promo.per_user_limit THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'per_user_limit');
  END IF;

  INSERT INTO public.promo_code_redemptions
    (promo_code_id, code, user_id, context, awarded_by)
  VALUES (v_promo.id, v_promo.code, p_user_id, COALESCE(p_context, '{}'::jsonb), v_uid);

  UPDATE public.promo_codes SET used_count = used_count + 1 WHERE id = v_promo.id;

  INSERT INTO public.notifications (user_id, title, body)
  VALUES (p_user_id, 'Promo Code Awarded',
          'You received promo code ' || v_promo.code || '. Open the quiz store to redeem it.');

  RETURN jsonb_build_object('ok', true, 'code', v_promo.code, 'kind', v_promo.kind);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.award_promo_code(uuid, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.award_promo_code(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.award_promo_code(uuid, text, jsonb) TO authenticated;

-- ── Redeem (user) — enforces active/expiry/limits ───────────────────────────
CREATE OR REPLACE FUNCTION public.redeem_promo_code(
  p_code    text,
  p_context jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_promo public.promo_codes%rowtype;
  v_used  int;
  v_total int;
  v_event uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_code IS NULL OR trim(p_code) = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'empty_code');
  END IF;

  SELECT * INTO v_promo FROM public.promo_codes
   WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF NOT v_promo.active THEN RETURN jsonb_build_object('ok', false, 'reason', 'inactive'); END IF;
  IF v_promo.expires_at IS NOT NULL AND v_promo.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;
  IF v_promo.max_uses IS NOT NULL AND v_promo.used_count >= v_promo.max_uses THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'exhausted');
  END IF;

  SELECT count(*) INTO v_used FROM public.promo_code_redemptions
   WHERE promo_code_id = v_promo.id AND user_id = v_uid;
  IF v_promo.per_user_limit > 0 AND v_used >= v_promo.per_user_limit THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'per_user_limit');
  END IF;

  -- Apply the effect.
  IF v_promo.kind = 'cc' THEN
    UPDATE public.profiles
       SET coins = COALESCE(coins, 0) + v_promo.value::int,
           balance_cc = COALESCE(balance_cc, 0) + v_promo.value::int
     WHERE id = v_uid;
    INSERT INTO public.coin_redemptions
      (user_id, amount, redemption_type, description, status)
    VALUES (v_uid, v_promo.value::int, 'promo_code_cc',
            'Promo code ' || v_promo.code, 'completed');
  ELSIF v_promo.kind = 'quiz_pass' THEN
    v_event := NULLIF(p_context->>'event_id', '')::uuid;
    IF v_event IS NOT NULL THEN
      INSERT INTO public.quiz_passes
        (event_id, user_id, payment_method, amount_cc, status)
      VALUES (v_event, v_uid, 'promo_code', 0, 'paid')
      ON CONFLICT (event_id, user_id)
      DO UPDATE SET status = 'paid', payment_method = 'promo_code';
    END IF;
  END IF;
  -- subscription_discount / event_entry: recorded for the consumer to apply.

  INSERT INTO public.promo_code_redemptions
    (promo_code_id, code, user_id, context)
  VALUES (v_promo.id, v_promo.code, v_uid, COALESCE(p_context, '{}'::jsonb));

  UPDATE public.promo_codes SET used_count = used_count + 1 WHERE id = v_promo.id;

  SELECT used_count INTO v_total FROM public.promo_codes WHERE id = v_promo.id;

  RETURN jsonb_build_object('ok', true, 'kind', v_promo.kind,
                            'value', v_promo.value, 'code', v_promo.code,
                            'used_count', v_total);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.redeem_promo_code(text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.redeem_promo_code(text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.redeem_promo_code(text, jsonb) TO authenticated;

-- ── Staff listings ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_promo_codes(p_only_active boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT c.id, c.code, c.kind, c.value, c.description, c.max_uses,
             c.per_user_limit, c.used_count, c.expires_at, c.active,
             c.created_by, c.created_at,
             COALESCE(r.redemptions, 0) AS redemptions,
             COALESCE(r.unique_users, 0) AS unique_users
        FROM public.promo_codes c
        LEFT JOIN (
          SELECT promo_code_id, count(*) AS redemptions,
                 count(DISTINCT user_id) AS unique_users
            FROM public.promo_code_redemptions
           GROUP BY promo_code_id
        ) r ON r.promo_code_id = c.id
       WHERE (NOT p_only_active OR c.active)
    ) x;
$$;

REVOKE EXECUTE ON FUNCTION public.list_promo_codes(boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_promo_codes(boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.list_promo_codes(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_promo_code_redemptions(p_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(row_to_json(x) ORDER BY x.redeemed_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.id, r.code, r.user_id, r.context, r.awarded_by, r.redeemed_at,
             p.full_name, p.tenant_id
        FROM public.promo_code_redemptions r
        LEFT JOIN public.profiles p ON p.id = r.user_id
       WHERE p_code IS NULL OR r.code = upper(trim(p_code))
       ORDER BY r.redeemed_at DESC
       LIMIT 500
    ) x;
$$;

REVOKE EXECUTE ON FUNCTION public.list_promo_code_redemptions(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_promo_code_redemptions(text) FROM public;
GRANT EXECUTE ON FUNCTION public.list_promo_code_redemptions(text) TO authenticated;

-- ── Set active (staff) ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_promo_code_active(
  p_promo_id uuid,
  p_active   boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not authorised'; END IF;
  UPDATE public.promo_codes SET active = p_active WHERE id = p_promo_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'active', p_active);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_promo_code_active(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_promo_code_active(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.set_promo_code_active(uuid, boolean) TO authenticated;
