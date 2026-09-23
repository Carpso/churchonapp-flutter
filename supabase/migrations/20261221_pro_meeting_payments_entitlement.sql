-- Pro Business Meeting: payments + entitlement (corrected against the REAL schema:
-- meeting_subscriptions is USER-scoped: user_id, plan_type, start_date, end_date, is_active, payment_ref)
ALTER TABLE public.meeting_subscriptions
  ADD COLUMN IF NOT EXISTS amount_kwacha numeric,
  ADD COLUMN IF NOT EXISTS coa_payment_id uuid,
  ADD COLUMN IF NOT EXISTS auto_renew boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_ref text,
  ADD COLUMN IF NOT EXISTS coa_cut_kwacha numeric;

INSERT INTO public.platform_settings (key, value) VALUES
  ('meeting_pro_monthly_kwacha','150'),
  ('meeting_pro_yearly_kwacha','1500'),
  ('coa_meeting_cut_percent','0.30')
ON CONFLICT (key) DO NOTHING;

DROP FUNCTION IF EXISTS public.meeting_entitlement(uuid);
DROP FUNCTION IF EXISTS public.request_meeting_subscription(text);
DROP FUNCTION IF EXISTS public.activate_meeting_subscription(text);
DROP FUNCTION IF EXISTS public.get_meeting_admin_report(int);
CREATE OR REPLACE FUNCTION public.is_platform_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid()
    AND p.role IN ('superadmin','super_admin','coa_employee','employee'));
$fn$;

CREATE OR REPLACE FUNCTION public.meeting_entitlement(p_user_id uuid DEFAULT auth.uid())
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE s public.meeting_subscriptions;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('is_pro',false,'plan',null,'expires_at',null,'max_participants',5,'can_record',false,'can_recur',false);
  END IF;
  SELECT * INTO s FROM public.meeting_subscriptions WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1;
  IF s.id IS NULL OR NOT COALESCE(s.is_active,false) OR (s.end_date IS NOT NULL AND s.end_date <= now()) THEN
    RETURN jsonb_build_object('is_pro',false,'plan',null,'expires_at',null,'max_participants',5,'can_record',false,'can_recur',false);
  END IF;
  RETURN jsonb_build_object('is_pro',true,'plan',s.plan_type,'expires_at',s.end_date,'max_participants',100,'can_record',true,'can_recur',true);
END $fn$;

CREATE OR REPLACE FUNCTION public.request_meeting_subscription(p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_amt numeric; v_ref text; v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_plan NOT IN ('monthly','yearly') THEN RAISE EXCEPTION 'invalid_plan'; END IF;
  SELECT COALESCE((SELECT value::numeric FROM public.platform_settings
      WHERE key = CASE WHEN p_plan='monthly' THEN 'meeting_pro_monthly_kwacha' ELSE 'meeting_pro_yearly_kwacha' END),
    CASE WHEN p_plan='monthly' THEN 150 ELSE 1500 END) INTO v_amt;
  v_ref := 'COA-MTG-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  INSERT INTO public.coa_payments (user_id, service_type, amount, payment_ref, status, category, metadata)
  VALUES (v_user, 'meeting_subscription', v_amt, v_ref, 'pending', 'meeting',
    jsonb_build_object('user_id', v_user, 'plan', p_plan));
  RETURN jsonb_build_object('payment_ref', v_ref, 'amount_kwacha', v_amt, 'plan', p_plan);
END $fn$;

CREATE OR REPLACE FUNCTION public.activate_meeting_subscription(p_payment_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_amt numeric; v_plan text; v_pay uuid; v_end timestamptz;
BEGIN
  SELECT amount, COALESCE(metadata->>'plan','monthly'), id INTO v_amt, v_plan, v_pay
  FROM public.coa_payments
  WHERE payment_ref = p_payment_ref AND status IN ('approved','completed','confirmed','settled')
  LIMIT 1;
  IF v_amt IS NULL THEN RAISE EXCEPTION 'payment_not_confirmed'; END IF;
  v_end := now() + CASE WHEN v_plan='yearly' THEN interval '365 days' ELSE interval '30 days' END;
  UPDATE public.meeting_subscriptions SET is_active=false WHERE user_id = auth.uid() AND is_active;
  INSERT INTO public.meeting_subscriptions (user_id, plan_type, start_date, end_date, is_active, payment_ref, amount_kwacha, coa_payment_id, coa_cut_kwacha)
  VALUES (auth.uid(), v_plan, now(), v_end, true, p_payment_ref, v_amt, v_pay,
    ROUND(v_amt * COALESCE((SELECT value::numeric FROM public.platform_settings WHERE key='coa_meeting_cut_percent'),0.30), 2));
  RETURN jsonb_build_object('is_pro',true,'plan',v_plan,'expires_at',v_end,'amount_kwacha',v_amt);
END $fn$;

CREATE OR REPLACE FUNCTION public.get_meeting_admin_report(p_days int DEFAULT 30)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT CASE WHEN public.is_platform_staff() THEN jsonb_build_object(
    'active_count', (SELECT count(*) FROM public.meeting_subscriptions WHERE is_active),
    'mrr_kwacha', (SELECT COALESCE(sum(amount_kwacha),0) FROM public.meeting_subscriptions WHERE is_active AND plan_type='monthly'),
    'collected_kwacha', (SELECT COALESCE(sum(amount),0) FROM public.coa_payments WHERE category='meeting' AND status IN ('approved','completed','confirmed','settled') AND created_at > now() - (p_days||' days')::interval),
    'coa_cut_kwacha', (SELECT COALESCE(sum(coa_cut_kwacha),0) FROM public.meeting_subscriptions WHERE created_at > now() - (p_days||' days')::interval),
    'refunds', (SELECT count(*) FROM public.meeting_subscriptions WHERE refunded_at IS NOT NULL),
    'subscriptions', (SELECT COALESCE(jsonb_agg(to_jsonb(s)),'[]'::jsonb) FROM public.meeting_subscriptions s)
  ) ELSE NULL END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.meeting_entitlement(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.request_meeting_subscription(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.activate_meeting_subscription(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_meeting_admin_report(int) FROM anon;