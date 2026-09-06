-- ═══════════════════════════════════════════════════════════════
-- Multi-tenant tithe/offering recipient resolution + payout task role
-- 1. payout_tasks.recipient_role — the tithe recipient the giver elected
--    (pastor / bishop / treasurer…), resolved server-side, never trusted
--    from the client as a phone number.
-- 2. enqueue_payout_task gains p_recipient_role (back-compatible: old
--    6-arg callers keep working, it defaults to NULL).
-- 3. Church auto-payout RPCs stop filtering on treasurer_phone alone —
--    they use the full church receiving chain:
--      treasurer_phone -> contact_phone -> pastor_phone ->
--      any leadership profile phone in the same tenant
--    so churches that only have a pastor/contact number still get paid.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.payout_tasks
  ADD COLUMN IF NOT EXISTS recipient_role TEXT;

-- Keep old signature callable while adding the role argument.
DROP FUNCTION IF EXISTS public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.enqueue_payout_task(
  p_source TEXT,
  p_source_ref TEXT,
  p_payment_ref TEXT,
  p_recipient_user_id UUID,
  p_recipient_phone TEXT,
  p_gross_amount NUMERIC,
  p_recipient_role TEXT DEFAULT NULL
) RETURNS public.payout_tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_task public.payout_tasks;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_source NOT IN ('giving','order','ride','delivery','escrow','ride_cut','delivery_cut') THEN
    RAISE EXCEPTION 'Invalid settlement source';
  END IF;
  IF p_gross_amount IS NULL OR p_gross_amount <= 0 OR p_gross_amount > 100000 THEN
    RAISE EXCEPTION 'Invalid gross amount';
  END IF;
  IF p_recipient_user_id IS NOT NULL AND p_recipient_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot settle a payout to yourself';
  END IF;
  IF p_recipient_phone IS NOT NULL THEN
    p_recipient_phone := regexp_replace(p_recipient_phone, '\D', '', 'g');
    IF length(p_recipient_phone) = 9 THEN
      p_recipient_phone := '260' || p_recipient_phone;
    ELSIF length(p_recipient_phone) = 10 AND p_recipient_phone LIKE '0%' THEN
      p_recipient_phone := '260' || substring(p_recipient_phone FROM 2);
    END IF;
    IF p_recipient_phone = '' THEN
      p_recipient_phone := NULL;
    END IF;
  END IF;
  IF p_payment_ref IS NULL AND p_source_ref IS NULL THEN
    RAISE EXCEPTION 'A payment reference or source reference is required';
  END IF;

  -- Only allow leadership roles to be designated as a tithe recipient.
  IF p_recipient_role IS NOT NULL
     AND lower(p_recipient_role) NOT IN (
       'pastor','bishop','treasurer','general_secretary','general_treasurer',
       'apostle','prophet','admin'
     ) THEN
    p_recipient_role := NULL;
  END IF;
  IF p_recipient_role IS NOT NULL THEN
    p_recipient_role := lower(p_recipient_role);
  END IF;

  INSERT INTO public.payout_tasks
    (user_id, source, source_ref, payment_ref, recipient_user_id, recipient_phone, recipient_role, gross_amount)
  VALUES
    (auth.uid(), p_source, p_source_ref, p_payment_ref, p_recipient_user_id, p_recipient_phone, p_recipient_role, p_gross_amount)
  ON CONFLICT (payment_ref, source, source_ref) DO NOTHING;

  SELECT * INTO v_task FROM public.payout_tasks
  WHERE user_id = auth.uid()
    AND source = p_source
    AND COALESCE(source_ref, '') = COALESCE(p_source_ref, '')
    AND COALESCE(payment_ref, '') = COALESCE(p_payment_ref, '')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_task IS NULL THEN
    RAISE EXCEPTION 'Could not enqueue settlement task';
  END IF;
  RETURN v_task;
END;
$$;

GRANT EXECUTE ON FUNCTION public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC, TEXT)
  TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC, TEXT)
  FROM anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_payout_task(TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC, TEXT)
  FROM PUBLIC;

-- ── Church receiving chain (SQL mirror of settlement.ts resolveChurchRecipient)
-- Returns the first usable 260XXXXXXXXX payout number for a church:
--   treasurer_phone -> contact_phone -> pastor_phone -> leadership profile phone
CREATE OR REPLACE FUNCTION public.church_recipient_phone(p_church_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_phone TEXT := NULL;
  v_raw   TEXT := NULL;
  v_role  TEXT;
BEGIN
  SELECT COALESCE(NULLIF(btrim(treasurer_phone::text), ''),
                  NULLIF(btrim(contact_phone::text), ''),
                  NULLIF(btrim(pastor_phone::text), ''))
    INTO v_raw
  FROM public.churches
  WHERE id::text = p_church_id;

  IF v_raw IS NULL THEN
    FOR v_role IN
      SELECT unnest(ARRAY['treasurer','general_treasurer','pastor','bishop',
                          'general_secretary','apostle','prophet','admin'])
    LOOP
      SELECT NULLIF(btrim(p.phone_number::text), '')
        INTO v_raw
      FROM public.profiles p
      WHERE p.tenant_id = p_church_id
        AND p.role = v_role
      LIMIT 1;
      EXIT WHEN v_raw IS NOT NULL;
    END LOOP;
  END IF;

  IF v_raw IS NULL THEN
    RETURN NULL;
  END IF;

  v_phone := regexp_replace(v_raw, '\D', '', 'g');
  IF length(v_phone) = 9 THEN
    v_phone := '260' || v_phone;
  ELSIF length(v_phone) = 10 AND v_phone LIKE '0%' THEN
    v_phone := '260' || substring(v_phone FROM 2);
  END IF;

  IF v_phone IS NULL OR v_phone NOT LIKE '260_________' THEN
    RETURN NULL;
  END IF;
  RETURN v_phone;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.church_recipient_phone(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.church_recipient_phone(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.church_recipient_phone(TEXT) TO service_role;

-- ── Auto-payout core: use the full receiving chain instead of treasurer_phone
CREATE OR REPLACE FUNCTION public._church_withdrawable_balances_svc()
RETURNS TABLE (
  church_id TEXT,
  church_name TEXT,
  treasurer_phone TEXT,
  gross_collected NUMERIC,
  committed_giving NUMERIC,
  in_flight_withdrawals NUMERIC,
  withdrawable NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH confirmed AS (
    SELECT c.metadata->>'tenant_id' AS church_id,
           COALESCE(SUM((c.amount)::numeric), 0) AS gross
    FROM public.coa_payments c
    WHERE c.status IN ('approved','completed','confirmed','settled')
      AND c.metadata->>'tenant_id' IS NOT NULL
      AND (c.created_at >= TIMESTAMPTZ '2026-08-13 00:00:00+00'
           OR EXISTS (
             SELECT 1 FROM public.payout_tasks t
             WHERE t.payment_ref = c.payment_ref AND t.source = 'giving'
           ))
    GROUP BY 1
  ),
  committed AS (
    SELECT p.metadata->>'tenant_id' AS church_id,
           COALESCE(SUM(t.gross_amount), 0) AS gross
    FROM public.payout_tasks t
    JOIN public.coa_payments p ON p.payment_ref = t.payment_ref
    WHERE t.source = 'giving'
      AND t.status IN ('pending','processing','paid')
      AND p.metadata->>'tenant_id' IS NOT NULL
    GROUP BY 1
  ),
  inflight AS (
    SELECT w.church_id,
           COALESCE(SUM(w.gross_amount), 0) AS gross
    FROM public.church_withdrawals w
    WHERE w.status IN ('pending','processing','paid')
    GROUP BY 1
  )
  SELECT
    ch.id::text AS church_id,
    ch.name::text AS church_name,
    public.church_recipient_phone(ch.id::text) AS treasurer_phone,
    COALESCE(cf.gross, 0) AS gross_collected,
    COALESCE(cm.gross, 0) AS committed_giving,
    COALESCE(ifw.gross, 0) AS in_flight_withdrawals,
    GREATEST(0, COALESCE(cf.gross, 0) - COALESCE(cm.gross, 0) - COALESCE(ifw.gross, 0)) AS withdrawable
  FROM public.churches ch
  LEFT JOIN confirmed cf ON cf.church_id = ch.id::text
  LEFT JOIN committed cm ON cm.church_id = ch.id::text
  LEFT JOIN inflight ifw ON ifw.church_id = ch.id::text
  WHERE public.church_recipient_phone(ch.id::text) IS NOT NULL
    AND COALESCE(cf.gross, 0) > 0
$$;

REVOKE EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() FROM anon;
REVOKE EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() TO service_role;
