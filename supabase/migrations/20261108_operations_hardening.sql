-- 20261108: production operations hardening
-- Money movement, quiz evidence, Carpso state transitions, and dashboard scope.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Payment anchors: clients may create only their own pending anchor.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'coa_payments' AND cmd = 'INSERT'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.coa_payments', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "coa_payments_pending_insert"
  ON public.coa_payments FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id AND lower(coalesce(status, 'pending')) = 'pending');

DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'coa_payments' AND cmd = 'UPDATE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.coa_payments', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "coa_payments_admin_update"
  ON public.coa_payments FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'coa_employee')
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'coa_employee')
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Church Coins and quiz evidence: no client-forged ledger rows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.add_coins(user_id UUID, amount INTEGER)
RETURNS VOID SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF amount IS NULL OR amount > 100000 OR amount < -100000 THEN
    RAISE EXCEPTION 'Coin amount out of bounds';
  END IF;
  UPDATE public.profiles
  SET coins = coalesce(coins, 0) + amount,
      balance_cc = coalesce(balance_cc, 0) + amount
  WHERE id = user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.add_coins(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_coins(UUID, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.deduct_coins(user_id UUID, amount INTEGER)
RETURNS VOID SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE current_coins INTEGER;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF amount IS NULL OR amount < 0 OR amount > 100000 THEN
    RAISE EXCEPTION 'Coin amount out of bounds';
  END IF;
  SELECT coalesce(coins, 0) INTO current_coins FROM public.profiles WHERE id = user_id FOR UPDATE;
  IF current_coins < amount THEN RAISE EXCEPTION 'Insufficient coins'; END IF;
  UPDATE public.profiles SET coins = current_coins - amount, balance_cc = greatest(coalesce(balance_cc, 0) - amount, 0)
  WHERE id = user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.deduct_coins(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deduct_coins(UUID, INTEGER) TO authenticated;

DO $$
DECLARE t TEXT; p RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['coin_redemptions','quiz_passes','quiz_event_participants','pvp_matches','pvp_answers','daily_challenge_results','user_answered_questions'] LOOP
    FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t AND cmd='INSERT' LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, t);
    END LOOP;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Carpso live-location write policy and server-owned ride transitions.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='driver_locations' AND cmd IN ('INSERT','UPDATE') LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.driver_locations', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "driver_locations_owner_insert" ON public.driver_locations
  FOR INSERT TO authenticated
  WITH CHECK (driver_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('driver','rider','superadmin','coa_employee')
  ));
CREATE POLICY "driver_locations_owner_update" ON public.driver_locations
  FOR UPDATE TO authenticated
  USING (driver_id = auth.uid())
  WITH CHECK (driver_id = auth.uid());

CREATE OR REPLACE FUNCTION public.accept_ride_request(p_request_id UUID)
RETURNS public.ride_requests SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); v public.ride_requests;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v FROM public.ride_requests WHERE id = p_request_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'pending' THEN RAISE EXCEPTION 'Ride is no longer available'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=uid AND p.role IN ('driver','rider','admin','pastor','bishop','superadmin','coa_employee')) THEN
    RAISE EXCEPTION 'Driver role required';
  END IF;
  IF v.tenant_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id=uid AND p.tenant_id IS NOT NULL AND p.tenant_id <> v.tenant_id::text
  ) THEN RAISE EXCEPTION 'Ride belongs to another tenant'; END IF;
  UPDATE public.ride_requests SET driver_id=uid, status='accepted', negotiation_status='accepted', fare_locked_at=now(), last_offer_by=NULL
  WHERE id=p_request_id AND status='pending' RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.accept_ride_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_ride_request(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_ride_payment(p_request_id UUID, p_payment_ref TEXT)
RETURNS VOID SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE r public.ride_requests; p public.coa_payments;
BEGIN
  SELECT * INTO r FROM public.ride_requests WHERE id=p_request_id FOR UPDATE;
  IF r.rider_id <> auth.uid() THEN RAISE EXCEPTION 'Only the rider can confirm payment'; END IF;
  SELECT * INTO p FROM public.coa_payments WHERE payment_ref=p_payment_ref AND user_id=auth.uid()
    AND status IN ('approved','completed','confirmed','settled') LIMIT 1;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Confirmed payment anchor required'; END IF;
  IF p.amount < coalesce(r.negotiated_fare, r.offered_fare) THEN RAISE EXCEPTION 'Payment is below the locked fare'; END IF;
  UPDATE public.ride_requests SET payment_ref=p_payment_ref, payment_status='paid', paid_at=now()
  WHERE id=p_request_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_ride_payment(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_ride_payment(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_ride_status(p_request_id UUID, p_status TEXT)
RETURNS public.ride_requests SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); r public.ride_requests;
BEGIN
  IF p_status NOT IN ('arrived','in_progress','completed','cancelled') THEN RAISE EXCEPTION 'Invalid ride transition'; END IF;
  SELECT * INTO r FROM public.ride_requests WHERE id=p_request_id FOR UPDATE;
  IF r.id IS NULL OR (uid <> r.rider_id AND uid <> r.driver_id) THEN RAISE EXCEPTION 'Not a ride participant'; END IF;
  IF p_status='completed' AND (r.payment_status <> 'paid' OR r.payment_ref IS NULL) THEN RAISE EXCEPTION 'Confirmed payment required'; END IF;
  IF p_status='arrived' AND r.status <> 'accepted' THEN RAISE EXCEPTION 'Ride must be accepted first'; END IF;
  IF p_status='in_progress' AND r.status NOT IN ('accepted','arrived') THEN RAISE EXCEPTION 'Ride is not ready to start'; END IF;
  IF p_status='completed' AND r.status NOT IN ('accepted','arrived','in_progress') THEN RAISE EXCEPTION 'Ride is not in progress'; END IF;
  IF p_status='cancelled' AND r.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Ride already closed'; END IF;
  UPDATE public.ride_requests SET status=p_status WHERE id=p_request_id RETURNING * INTO r;
  RETURN r;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.transition_ride_status(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(UUID, TEXT) TO authenticated;

-- Server derives driver, fare, payment anchor, and both platform/driver tasks.
CREATE OR REPLACE FUNCTION public.enqueue_ride_settlements(p_request_id UUID)
RETURNS INTEGER SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); r public.ride_requests; p public.coa_payments; fare NUMERIC; cut NUMERIC;
BEGIN
  SELECT * INTO r FROM public.ride_requests WHERE id=p_request_id FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'completed' OR r.driver_id IS NULL THEN RAISE EXCEPTION 'Ride is not settleable'; END IF;
  IF uid <> r.rider_id AND uid <> r.driver_id AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=uid AND role IN ('superadmin','coa_employee')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO p FROM public.coa_payments WHERE payment_ref=r.payment_ref AND user_id=r.rider_id AND status IN ('approved','completed','confirmed','settled') LIMIT 1;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Confirmed payment anchor required'; END IF;
  fare := coalesce(r.negotiated_fare, r.offered_fare);
  SELECT coalesce((SELECT value::numeric FROM public.platform_settings WHERE key='business_cut_percent'), 0.10) INTO cut;
  INSERT INTO public.payout_tasks(user_id,source,source_ref,payment_ref,gross_amount,tenant_id)
  VALUES (r.driver_id,'ride',r.id::text,r.payment_ref,round(fare*(1-cut),2),r.tenant_id::text)
  ON CONFLICT (payment_ref,source,source_ref) DO NOTHING;
  INSERT INTO public.payout_tasks(user_id,source,source_ref,payment_ref,gross_amount,tenant_id)
  VALUES (r.driver_id,'ride_cut',r.id::text,r.payment_ref,round(fare*cut,2),r.tenant_id::text)
  ON CONFLICT (payment_ref,source,source_ref) DO NOTHING;
  RETURN 2;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.enqueue_ride_settlements(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_ride_settlements(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_delivery_payment(p_delivery_id UUID, p_payment_ref TEXT)
RETURNS VOID SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); d public.delivery_requests; p public.coa_payments;
BEGIN
  SELECT * INTO d FROM public.delivery_requests WHERE id=p_delivery_id FOR UPDATE;
  IF d.sender_id <> uid THEN RAISE EXCEPTION 'Only the sender can confirm payment'; END IF;
  SELECT * INTO p FROM public.coa_payments WHERE payment_ref=p_payment_ref AND user_id=uid
    AND status IN ('approved','completed','confirmed','settled') LIMIT 1;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Confirmed payment anchor required'; END IF;
  IF p.amount < coalesce(d.negotiated_fare, d.offered_fare) THEN RAISE EXCEPTION 'Payment is below the locked fare'; END IF;
  UPDATE public.delivery_requests SET payment_ref=p_payment_ref, payment_status='paid', paid_at=now()
  WHERE id=p_delivery_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_delivery_payment(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_delivery_payment(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_delivery_status(p_delivery_id UUID, p_status TEXT)
RETURNS public.delivery_requests SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); d public.delivery_requests;
BEGIN
  IF p_status NOT IN ('arrived','picked_up','in_transit','delivered','cancelled') THEN RAISE EXCEPTION 'Invalid delivery transition'; END IF;
  SELECT * INTO d FROM public.delivery_requests WHERE id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR (uid <> d.sender_id AND uid <> d.driver_id) THEN RAISE EXCEPTION 'Not a delivery participant'; END IF;
  IF p_status='delivered' AND (d.payment_status <> 'paid' OR d.payment_ref IS NULL) THEN RAISE EXCEPTION 'Confirmed payment required'; END IF;
  IF p_status='delivered' AND d.status NOT IN ('accepted','arrived','picked_up','in_transit') THEN RAISE EXCEPTION 'Delivery is not in progress'; END IF;
  IF p_status='cancelled' AND d.status IN ('delivered','cancelled') THEN RAISE EXCEPTION 'Delivery already closed'; END IF;
  UPDATE public.delivery_requests SET status=p_status WHERE id=p_delivery_id RETURNING * INTO d;
  RETURN d;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.transition_delivery_status(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_delivery_status(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_delivery_settlements(p_delivery_id UUID)
RETURNS INTEGER SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE uid UUID := auth.uid(); d public.delivery_requests; p public.coa_payments; fare NUMERIC; cut NUMERIC;
BEGIN
  SELECT * INTO d FROM public.delivery_requests WHERE id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'delivered' OR d.driver_id IS NULL THEN RAISE EXCEPTION 'Delivery is not settleable'; END IF;
  IF uid <> d.sender_id AND uid <> d.driver_id AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=uid AND role IN ('superadmin','coa_employee')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO p FROM public.coa_payments WHERE payment_ref=d.payment_ref AND user_id=d.sender_id AND status IN ('approved','completed','confirmed','settled') LIMIT 1;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Confirmed payment anchor required'; END IF;
  fare := coalesce(d.negotiated_fare, d.offered_fare);
  SELECT coalesce((SELECT value::numeric FROM public.platform_settings WHERE key='business_cut_percent'), 0.10) INTO cut;
  INSERT INTO public.payout_tasks(user_id,source,source_ref,payment_ref,gross_amount,tenant_id)
  VALUES (d.driver_id,'delivery',d.id::text,d.payment_ref,round(fare*(1-cut),2),d.tenant_id::text)
  ON CONFLICT (payment_ref,source,source_ref) DO NOTHING;
  INSERT INTO public.payout_tasks(user_id,source,source_ref,payment_ref,gross_amount,tenant_id)
  VALUES (d.driver_id,'delivery_cut',d.id::text,d.payment_ref,round(fare*cut,2),d.tenant_id::text)
  ON CONFLICT (payment_ref,source,source_ref) DO NOTHING;
  RETURN 2;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.enqueue_delivery_settlements(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_delivery_settlements(UUID) TO authenticated;

-- Prevent duplicate source-only tasks when clients retry completion.
CREATE UNIQUE INDEX IF NOT EXISTS payout_tasks_source_ref_null_payment_uidx
  ON public.payout_tasks(source, source_ref)
  WHERE payment_ref IS NULL AND source_ref IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Dashboard/report and attendance RPC authorization.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tenant_member_attendance(
  p_tenant_id TEXT, p_months INT DEFAULT 3
)
RETURNS TABLE(user_id UUID, full_name TEXT, attended INT, total_services INT, attendance_rate NUMERIC)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH allowed AS (
    SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
      AND (p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin','leader','general_secretary')
        OR p.tenant_id=p_tenant_id)
  ), period AS (
    SELECT (date_trunc('month', now()) - (p_months || ' months')::interval)::date AS start_date
  ), services AS (
    SELECT count(DISTINCT service_date)::INT AS total FROM public.member_attendance
    WHERE tenant_id=p_tenant_id AND service_date >= (SELECT start_date FROM period)
  ), attendance AS (
    SELECT user_id, count(DISTINCT service_date)::INT AS attended FROM public.member_attendance
    WHERE tenant_id=p_tenant_id AND service_date >= (SELECT start_date FROM period) GROUP BY user_id
  )
  SELECT p.id, coalesce(p.full_name,'Unnamed member'), coalesce(a.attended,0), s.total,
    CASE WHEN s.total > 0 THEN round(coalesce(a.attended,0)::numeric/s.total*100,1) ELSE 0 END
  FROM public.profiles p CROSS JOIN services s LEFT JOIN attendance a ON a.user_id=p.id
  WHERE EXISTS (SELECT 1 FROM allowed) AND p.tenant_id=p_tenant_id AND p.role='member'
  ORDER BY coalesce(a.attended,0) DESC, p.full_name;
$$;
REVOKE EXECUTE ON FUNCTION public.get_tenant_member_attendance(TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tenant_member_attendance(TEXT, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_member_attendance(
  p_user_id UUID, p_tenant_id TEXT, p_service_date DATE, p_service_type TEXT DEFAULT 'Sunday Service'
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
    AND p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin','leader','general_secretary')
    AND (p.tenant_id=p_tenant_id OR p.organization_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'Not authorized for this tenant';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=p_user_id AND p.tenant_id=p_tenant_id) THEN
    RAISE EXCEPTION 'Member is outside this tenant';
  END IF;
  INSERT INTO public.member_attendance(user_id,tenant_id,service_date,service_type,checked_in_by)
  VALUES(p_user_id,p_tenant_id,p_service_date,coalesce(nullif(p_service_type,''),'Sunday Service'),auth.uid())
  ON CONFLICT(user_id,tenant_id,service_date,service_type) DO NOTHING;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_member_attendance(UUID,TEXT,DATE,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_member_attendance(UUID,TEXT,DATE,TEXT) TO authenticated;

-- Remove public report policies left by early migrations.
DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN SELECT policyname, tablename FROM pg_policies WHERE schemaname='public' AND tablename IN ('service_reports','pastor_reports') LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, p.tablename);
  END LOOP;
END $$;
CREATE POLICY "service_reports_tenant_read" ON public.service_reports FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND
    (p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin') OR p.tenant_id::text=service_reports.tenant_id::text))
);
CREATE POLICY "service_reports_leader_insert" ON public.service_reports FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role IN ('superadmin','coa_employee','bishop','apostle','pastor','admin') AND p.tenant_id::text=service_reports.tenant_id::text)
);
CREATE POLICY "pastor_reports_org_read" ON public.pastor_reports FOR SELECT TO authenticated USING (
  pastor_id=auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role IN ('superadmin','coa_employee','bishop','apostle') AND p.organization_id::text=pastor_reports.organization_id::text)
);
CREATE POLICY "pastor_reports_leader_insert" ON public.pastor_reports FOR INSERT TO authenticated WITH CHECK (pastor_id=auth.uid());
