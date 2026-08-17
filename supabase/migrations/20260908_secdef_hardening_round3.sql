-- 20260908 — SECURITY HARDENING ROUND 3: remaining PUBLIC/anon EXECUTE sweep
-- (full DB audit, 2026-08-17)
--
-- Round 2 (20260907) fixed the worst offenders. This sweep completes the
-- cleanup: every remaining SECURITY DEFINER function that still had
-- PUBLIC (`{=X`) or anon EXECUTE was audited body-by-body (bodies dumped and
-- compared). Bodies are preserved EXACTLY from the live DB — only auth guards
-- are added and anon/PUBLIC grants stripped. Findings:
--
-- CRITICAL (body trusts client-supplied identity or has no check):
--   * insert_transaction_idempotent — anon could insert transactions for
--     ANY user/tenant (financial records forgery). Now requires
--     auth.uid() = p_user_id or service_role.
--   * redeem_coins_atomic — anon could spend ANY user's coins. Now requires
--     auth.uid() = p_user_id or service_role.
--   * process_payroll — anon could run payroll for any church. Now requires
--     platform admin OR church leadership with tenant match.
--   * reactivate_tenant / suspend_tenant / toggle_system_freeze — only
--     checked "logged in": ANY user could suspend ANY tenant or freeze the
--     WHOLE platform. Now require is_admin_or_employee().
--   * join_business_meeting / start_business_meeting — trusted client
--     p_user_id (join/start as anyone). Now requires auth.uid() = p_user_id.
--   * record_event_checkin — trusted client p_scanned_by. Scanner is now
--     auth.uid() and must belong to the event's church (or platform admin).
--   * get_organization_church_member_counts — anon could enumerate org
--     member counts. Now org-leadership-gated (mirrors get_organization_stats).
--   * get_platform_engagement_stats — anon could read platform analytics.
--     Now is_admin_or_employee() only.
--   * get_streaming_usage — any caller could read any church's usage.
--     Now caller's tenant must match (or platform admin).
--   * record_streaming_minutes (3 PUBLIC overloads) — anon could inflate
--     streaming usage for any church. Now tenant-scoped + authenticated.
--   * resolve_settlement_phone — anon could harvest treasurer/payout phone
--     numbers for any tenant. Now auth-gated + tenant-scoped.
--   * award_xp — same minting hole as award_user_xp. Now admin/employee only.
--   * next_id_sequence — anon could burn sequence numbers (DoS on codes).
--     Now authenticated only.
--   * increment_member_paid / increment_promo_redemption / increment_ad_impression /
--     increment_attendee_count / increment_group_collected / increment_klip_view /
--     increment_study_attendees / generate_meeting_code / heartbeat_presence —
--     anon could inflate counters. Now authenticated only.
--
-- Keep-by-design anon/PUBLIC: increment_website_view (public website counter).
-- Trigger functions keep no PUBLIC grant either (triggers fire internally).
-- Cron functions (cleanup_*) restricted to service_role.

-- ============================================================
-- CRITICAL body rewrites (original bodies + auth guards)
-- ============================================================

CREATE OR REPLACE FUNCTION public.insert_transaction_idempotent(p_idempotency_key text, p_user_id uuid, p_tenant_id uuid, p_amount double precision, p_type text, p_currency text DEFAULT 'ZMW'::text, p_payment_method text DEFAULT NULL::text, p_payment_ref text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_platform_fee double precision DEFAULT 0)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_existing_id UUID;
  v_new_id UUID;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF v_uid IS NOT NULL AND v_uid <> p_user_id AND NOT is_admin_or_employee() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  -- Check idempotency first
  SELECT transaction_id INTO v_existing_id
  FROM public.transaction_idempotency
  WHERE idempotency_key = p_idempotency_key;

  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  -- Insert transaction
  v_new_id := gen_random_uuid();
  INSERT INTO public.transactions (id, user_id, tenant_id, amount, category, payment_method, reference, platform_fee, status, created_at)
  VALUES (v_new_id, p_user_id, p_tenant_id, p_amount, p_type, p_payment_method, p_payment_ref, p_platform_fee, 'completed', now());

  -- Record idempotency key
  INSERT INTO public.transaction_idempotency (idempotency_key, transaction_id)
  VALUES (p_idempotency_key, v_new_id);

  -- Audit log
  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (p_user_id, 'transaction_created', 'transactions', v_new_id,
          jsonb_build_object('amount', p_amount, 'type', p_type, 'tenant_id', p_tenant_id::TEXT));

  RETURN v_new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.redeem_coins_atomic(p_user_id uuid, p_amount integer, p_redemption_type text, p_partner_id text, p_description text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_coins INT;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF v_uid IS NOT NULL AND v_uid <> p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT coins INTO current_coins
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF current_coins IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  IF current_coins < p_amount THEN
    RAISE EXCEPTION 'Insufficient coins. Current: %, Requested: %', current_coins, p_amount;
  END IF;

  UPDATE profiles
  SET coins = coins - p_amount
  WHERE id = p_user_id;

  INSERT INTO coin_redemptions (user_id, amount, redemption_type, partner_id, description, status)
  VALUES (p_user_id, p_amount, p_redemption_type, p_partner_id, p_description, 'completed');
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_payroll(p_tenant_id uuid, p_month integer, p_year integer, p_processed_by uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  emp RECORD;
  settings_rec RECORD;
  gross NUMERIC;
  taxable NUMERIC;
  paye NUMERIC := 0;
  napsa_ee NUMERIC := 0;
  napsa_er NUMERIC := 0;
  nhima_ee NUMERIC := 0;
  nhima_er NUMERIC := 0;
  sdl NUMERIC := 0;
  net NUMERIC;
  run_id UUID;
  total_gross NUMERIC := 0;
  total_paye NUMERIC := 0;
  total_napsa_ee NUMERIC := 0;
  total_napsa_er NUMERIC := 0;
  total_nhima_ee NUMERIC := 0;
  total_nhima_er NUMERIC := 0;
  total_sdl NUMERIC := 0;
  total_net NUMERIC := 0;
  emp_count INT := 0;
  band RECORD;
  taxable_remaining NUMERIC;
  band_width NUMERIC;
  band_amount NUMERIC;
  paye_result JSONB;
  band_data JSONB;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (
    is_admin_or_employee()
    OR (auth.uid() = p_processed_by AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.tenant_id::text = p_tenant_id::text
              AND p.role IN ('admin','pastor','bishop','general_treasurer','treasurer','general_secretary')
        ))
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  -- Get payroll settings
  SELECT * INTO settings_rec FROM payroll_settings WHERE tenant_id = p_tenant_id;
  IF settings_rec IS NULL THEN
    settings_rec := ROW(NULL, p_tenant_id, 4500, 1861.80, 5, 0.005,
      '[{"min":0,"max":4500,"rate":0},{"min":4501,"max":6800,"rate":0.20},{"min":6801,"max":9800,"rate":0.25},{"min":9801,"max":14500,"rate":0.30},{"min":14501,"max":null,"rate":0.35}]'::jsonb,
      now(), now());
  END IF;

  -- Create payroll run
  INSERT INTO payroll_runs (tenant_id, period_month, period_year, status, processed_by, processed_at)
  VALUES (p_tenant_id, p_month, p_year, 'processed', p_processed_by, now())
  RETURNING id INTO run_id;

  -- Process each active employee
  FOR emp IN SELECT * FROM employees WHERE tenant_id = p_tenant_id AND is_active = true
  LOOP
    gross := emp.gross_salary + COALESCE(emp.allowances, 0);

    -- PAYE (progressive bands)
    taxable := gross - settings_rec.tax_free_threshold;
    paye := 0;
    IF taxable > 0 THEN
      paye_result := calculate_paye(gross);
      paye := (paye_result->>'total_tax')::NUMERIC;
    END IF;

    -- NAPSA (5% employee, 5% employer, capped)
    napsa_ee := LEAST(gross * 0.05, settings_rec.napsa_cap);
    napsa_er := LEAST(gross * 0.05, settings_rec.napsa_cap);

    -- NHIMA (1% employee, 1% employer)
    nhima_ee := gross * 0.01;
    nhima_er := gross * 0.01;

    -- SDL (0.5% employer only, if 5+ employees)
    sdl := 0; -- calculated at run level

    net := gross - paye - napsa_ee - nhima_ee;

    -- Insert payslip
    INSERT INTO payslips (
      payroll_run_id, employee_id, tenant_id,
      basic_salary, allowances, benefits_in_kind, gross_salary,
      paye, napsa_employee, nhima_employee,
      napsa_employer, nhima_employer, sdl,
      total_deductions, net_pay, tax_breakdown, status
    ) VALUES (
      run_id, emp.id, p_tenant_id,
      emp.gross_salary, COALESCE(emp.allowances, 0), COALESCE(emp.benefits_in_kind, 0), gross,
      paye, napsa_ee, nhima_ee,
      napsa_er, nhima_er, 0,
      paye + napsa_ee + nhima_ee, net,
      COALESCE(paye_result, '{}'::jsonb), 'finalized'
    );

    -- Accumulate totals
    total_gross := total_gross + gross;
    total_paye := total_paye + paye;
    total_napsa_ee := total_napsa_ee + napsa_ee;
    total_napsa_er := total_napsa_er + napsa_er;
    total_nhima_ee := total_nhima_ee + nhima_ee;
    total_nhima_er := total_nhima_er + nhima_er;
    total_net := total_net + net;
    emp_count := emp_count + 1;
  END LOOP;

  -- SDL (0.5% of total gross, employer only, if 5+ employees)
  IF emp_count >= settings_rec.sdl_threshold THEN
    sdl := total_gross * settings_rec.sdl_rate;
  END IF;

  -- Update payroll run totals
  UPDATE payroll_runs SET
    total_gross = total_gross,
    total_paye = total_paye,
    total_napsa_employee = total_napsa_ee,
    total_napsa_employer = total_napsa_er,
    total_nhima_employee = total_nhima_ee,
    total_nhima_employer = total_nhima_er,
    total_sdl = sdl,
    total_net_pay = total_net,
    employee_count = emp_count
  WHERE id = run_id;

  -- Update SDL on payslips
  IF sdl > 0 THEN
    UPDATE payslips SET sdl = sdl / emp_count WHERE payroll_run_id = run_id;
  END IF;

  RETURN jsonb_build_object(
    'run_id', run_id,
    'employee_count', emp_count,
    'total_gross', total_gross,
    'total_paye', total_paye,
    'total_napsa_employee', total_napsa_ee,
    'total_napsa_employer', total_napsa_er,
    'total_nhima_employee', total_nhima_ee,
    'total_nhima_employer', total_nhima_er,
    'total_sdl', sdl,
    'total_net_pay', total_net
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reactivate_tenant(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL OR NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE public.tenants
  SET is_active = true
  WHERE id = p_tenant_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_reactivated', 'tenants', p_tenant_id, '{}');

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suspend_tenant(p_tenant_id uuid, p_reason text DEFAULT NULL::text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL OR NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE public.tenants
  SET is_active = false
  WHERE id = p_tenant_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, 'tenant_suspended', 'tenants', p_tenant_id,
          jsonb_build_object('reason', p_reason));

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.toggle_system_freeze(p_locked boolean, p_reason text DEFAULT NULL::text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL OR NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE public.system_lock_state
  SET is_locked = p_locked,
      reason = p_reason,
      locked_by = v_admin_id,
      locked_at = CASE WHEN p_locked THEN now() ELSE NULL END,
      unlock_at = CASE WHEN p_locked THEN now() + interval '1 hour' ELSE NULL END
  WHERE id = (SELECT id FROM public.system_lock_state ORDER BY created_at DESC LIMIT 1);

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
  VALUES (v_admin_id, CASE WHEN p_locked THEN 'system_freeze' ELSE 'system_unfreeze' END, 'system_lock_state', NULL,
          jsonb_build_object('reason', p_reason));

  RETURN p_locked;
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_business_meeting(p_meeting_id uuid, p_user_id uuid, p_role text DEFAULT 'participant'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_meeting RECORD;
  v_participant_count INTEGER;
  v_existing RECORD;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;
  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
  END IF;

  IF v_meeting.status = 'ended' OR v_meeting.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting has ended');
  END IF;

  SELECT COUNT(*) INTO v_participant_count
  FROM public.meeting_participants
  WHERE meeting_id = p_meeting_id AND left_at IS NULL;

  IF v_participant_count >= v_meeting.max_participants THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting is full (' || v_meeting.max_participants || ' participants max)');
  END IF;

  SELECT * INTO v_existing
  FROM public.meeting_participants
  WHERE meeting_id = p_meeting_id AND user_id = p_user_id;

  IF v_existing IS NOT NULL THEN
    UPDATE public.meeting_participants SET left_at = NULL WHERE id = v_existing.id;
    RETURN jsonb_build_object('success', true, 'participant_id', v_existing.id, 'rejoined', true);
  END IF;

  INSERT INTO public.meeting_participants (meeting_id, user_id, role)
  VALUES (p_meeting_id, p_user_id, p_role)
  RETURNING id INTO v_existing;

  RETURN jsonb_build_object('success', true, 'participant_id', v_existing.id, 'rejoined', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_business_meeting(p_meeting_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_meeting RECORD;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;
  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
  END IF;
  IF v_meeting.host_id != p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the host can start the meeting');
  END IF;
  UPDATE public.business_meetings SET status = 'active', started_at = now() WHERE id = p_meeting_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_event_checkin(p_registration_id uuid, p_event_id uuid, p_scanned_by uuid, p_device_info text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_result JSONB;
    v_scanner UUID := auth.uid();
BEGIN
    IF v_scanner IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    -- Scanner must belong to the event's church leadership, or be platform admin
    IF NOT (is_admin_or_employee() OR EXISTS (
        SELECT 1 FROM public.events e JOIN public.profiles p ON p.tenant_id = e.tenant_id::text
        WHERE e.id = p_event_id AND p.id = v_scanner AND p.role IN ('admin','pastor','bishop','general_secretary','event_admin')
    )) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    -- Update registration
    UPDATE public.event_registrations
    SET check_in_status = true, checked_in_at = now(), checked_in_by = v_scanner
    WHERE id = p_registration_id;

    -- Insert checkin record
    INSERT INTO public.event_checkins (event_id, registration_id, scanned_by, device_info)
    VALUES (p_event_id, p_registration_id, v_scanner, p_device_info)
    ON CONFLICT (registration_id) DO NOTHING;

    v_result := jsonb_build_object('success', true, 'registration_id', p_registration_id);
    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_organization_church_member_counts(p_org_id uuid)
RETURNS TABLE(church_id uuid, church_name text, member_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.id = me.tenant_id::uuid
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = p_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    RETURN QUERY
    SELECT
        c.id AS church_id,
        c.name AS church_name,
        COUNT(p.id) AS member_count
    FROM public.churches c
    LEFT JOIN public.profiles p
        ON p.tenant_id::uuid = c.id
    WHERE c.organization_id = p_org_id
    GROUP BY c.id, c.name
    ORDER BY c.name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_platform_engagement_stats(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_bible_audio_plays BIGINT;
    v_podcast_listens BIGINT;
    v_kids_activities BIGINT;
    v_quiz_sessions BIGINT;
    v_kids_progress_users BIGINT;
    v_cutoff TIMESTAMPTZ := now() - (p_days || ' days')::INTERVAL;
BEGIN
    IF NOT is_admin_or_employee() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    -- Bible audio plays (from attendance_logs with type indicating audio or bible activity)
    SELECT COUNT(*) INTO v_bible_audio_plays
    FROM public.attendance_logs
    WHERE created_at >= v_cutoff;

    -- Podcast listens (audio playback events)
    SELECT COUNT(*) INTO v_podcast_listens
    FROM public.attendance_logs
    WHERE created_at >= v_cutoff;

    -- Kids Zone activities (from kids_progress)
    SELECT COALESCE(SUM(weekly_activity_count), 0) INTO v_kids_activities
    FROM public.kids_progress
    WHERE updated_at >= v_cutoff;

    -- Kids Zone active users this period
    SELECT COUNT(DISTINCT user_id) INTO v_kids_progress_users
    FROM public.kids_progress
    WHERE updated_at >= v_cutoff;

    -- Bible quiz sessions (from quiz_results or game_scores)
    SELECT COUNT(*) INTO v_quiz_sessions
    FROM public.game_scores
    WHERE created_at >= v_cutoff;

    -- Fallback to sensible defaults
    v_bible_audio_plays := COALESCE(v_bible_audio_plays, 0);
    v_podcast_listens := COALESCE(v_podcast_listens, v_bible_audio_plays);
    v_kids_activities := COALESCE(v_kids_activities, 0);
    v_kids_progress_users := COALESCE(v_kids_progress_users, 0);
    v_quiz_sessions := COALESCE(v_quiz_sessions, 0);

    RETURN jsonb_build_object(
        'bible_audio_plays', v_bible_audio_plays,
        'podcast_listens', v_podcast_listens,
        'kids_activities', v_kids_activities,
        'kids_active_users', v_kids_progress_users,
        'quiz_sessions', v_quiz_sessions,
        'period_days', p_days
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_streaming_usage(p_church_id uuid)
RETURNS TABLE(minutes_used bigint, minutes_limit bigint, minutes_remaining bigint, can_stream boolean, week_start date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_week_start DATE := date_trunc('week', now())::date;
  v_used BIGINT;
  v_limit BIGINT;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (is_admin_or_employee() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND tenant_id = p_church_id::text)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT COALESCE(SUM(su.minutes_used), 0) INTO v_used
  FROM streaming_usage su
  WHERE su.church_id = p_church_id AND su.week_start = v_week_start;
  IF EXISTS (
    SELECT 1 FROM churches WHERE id = p_church_id
    AND subscription_status = 'paid'
    AND subscription_ends_at > now()
  ) THEN
    v_limit := 480;
  ELSE
    v_limit := 120;
  END IF;
  RETURN QUERY SELECT
    v_used,
    v_limit,
    GREATEST(v_limit - v_used, 0),
    (v_used < v_limit),
    v_week_start;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_streaming_minutes(p_church_id uuid, p_minutes bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_week_start DATE := date_trunc('week', now())::date;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (is_admin_or_employee() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND tenant_id = p_church_id::text)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  INSERT INTO streaming_usage (church_id, week_start, minutes)
  VALUES (p_church_id, v_week_start, p_minutes)
  ON CONFLICT (church_id, week_start)
  DO UPDATE SET minutes = streaming_usage.minutes + p_minutes;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_streaming_minutes(p_church_id uuid, p_minutes numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (is_admin_or_employee() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND tenant_id = p_church_id::text)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  INSERT INTO streaming_usage (church_id, week_start, minutes_used)
  VALUES (p_church_id, date_trunc('week', now())::date, GREATEST(p_minutes, 0))
  ON CONFLICT (church_id, week_start)
  DO UPDATE SET minutes_used = streaming_usage.minutes_used + EXCLUDED.minutes_used,
                updated_at = now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_streaming_minutes(p_church_id uuid, p_minutes numeric, p_peak_viewers integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_week_start DATE;
  v_is_trial BOOLEAN;
  v_limit NUMERIC;
  v_total_used NUMERIC;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (is_admin_or_employee() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND tenant_id = p_church_id::text)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  v_week_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::INT;

  SELECT subscription_status = 'trial' INTO v_is_trial
  FROM churches WHERE id = p_church_id;

  IF v_is_trial THEN
    v_limit := 10;
    v_total_used := COALESCE(
      (SELECT SUM(minutes_used) FROM streaming_usage WHERE church_id = p_church_id),
      0
    );
  ELSE
    v_limit := -1;
    v_total_used := 0;
  END IF;

  INSERT INTO streaming_usage (church_id, week_start, minutes_used, minutes_limit, stream_count, peak_viewers)
  VALUES (p_church_id, v_week_start, p_minutes, v_limit, 1, p_peak_viewers)
  ON CONFLICT (church_id, week_start) DO UPDATE SET
    minutes_used = streaming_usage.minutes_used + p_minutes,
    stream_count = streaming_usage.stream_count + 1,
    peak_viewers = GREATEST(streaming_usage.peak_viewers, p_peak_viewers),
    updated_at = now();

  RETURN jsonb_build_object(
    'total_minutes_used', COALESCE(v_total_used + p_minutes, p_minutes),
    'minutes_limit', v_limit,
    'can_stream', CASE WHEN v_limit = -1 THEN TRUE
                       ELSE COALESCE(v_total_used + p_minutes, p_minutes) < v_limit
                  END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_settlement_phone(p_tenant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_phone TEXT;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL AND auth.role() <> 'service_role' THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_uid IS NOT NULL AND NOT (is_admin_or_employee() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND tenant_id = p_tenant_id::text)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  -- Try churches.payout_mobile first
  SELECT payout_mobile INTO v_phone FROM public.churches WHERE tenant_id = p_tenant_id AND payout_mobile IS NOT NULL LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  -- Try churches.treasurer_phone
  SELECT treasurer_phone INTO v_phone FROM public.churches WHERE tenant_id = p_tenant_id AND treasurer_phone IS NOT NULL LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  -- Try pastor/admin profile phone
  SELECT phone_number INTO v_phone FROM public.profiles
    WHERE tenant_id = p_tenant_id::text
      AND role IN ('pastor', 'bishop', 'admin')
      AND phone_number IS NOT NULL
    LIMIT 1;
  IF v_phone IS NOT NULL THEN RETURN v_phone; END IF;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.award_xp(user_id uuid, amount integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  new_level INTEGER;
  old_level INTEGER;
  v_granter UUID := auth.uid();
BEGIN
  IF v_granter IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_granter AND role IN ('superadmin', 'coa_employee', 'employee')) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT level INTO old_level FROM profiles WHERE id = user_id;
  UPDATE profiles
  SET xp = COALESCE(xp, 0) + amount,
      level = calculate_level(COALESCE(xp, 0) + amount)
  WHERE id = user_id;

  SELECT level INTO new_level FROM profiles WHERE id = user_id;
  RETURN new_level - old_level; -- 0 = no level up, >0 = level up!
END;
$function$;

CREATE OR REPLACE FUNCTION public.next_id_sequence(seq_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  next_val BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  INSERT INTO public.id_sequences (name, value)
  VALUES (seq_name, 1)
  ON CONFLICT (name) DO UPDATE SET value = public.id_sequences.value + 1
  RETURNING value INTO next_val;
  RETURN LPAD(next_val::TEXT, 4, '0');
END;
$function$;

CREATE OR REPLACE FUNCTION public.generate_meeting_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  LOOP
    v_code := 'MTG-' || upper(substr(md5(random()::text), 1, 6));
    SELECT EXISTS(SELECT 1 FROM public.business_meetings WHERE meeting_code = v_code AND status != 'ended' AND status != 'cancelled') INTO v_exists;
    EXIT WHEN NOT v_exists;
  END LOOP;
  RETURN v_code;
END;
$function$;

-- ============================================================
-- Counter functions — authenticated only (bodies preserved)
-- ============================================================
CREATE OR REPLACE FUNCTION public.increment_member_paid(p_member_id uuid, p_amount integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE group_contribution_members SET paid = COALESCE(paid, 0) + p_amount, updated_at = now() WHERE id = p_member_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_member_paid(member_id uuid, amount double precision)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE group_contribution_members SET paid = COALESCE(paid, 0) + amount, updated_at = now() WHERE id = member_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_promo_redemption(campaign_id_str text, amount numeric DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.promo_campaigns SET current_redemptions = current_redemptions + 1, budget_spent_zmw = budget_spent_zmw + COALESCE(amount, 0) WHERE id = campaign_id_str::UUID;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_ad_impression(ad_id_str text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.tenant_ads SET impressions = impressions + 1 WHERE id = ad_id_str::UUID;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_attendee_count(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.events SET attendee_count = COALESCE(attendee_count, 0) + 1 WHERE id = p_event_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_group_collected(p_group_id uuid, p_amount integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.group_contributions SET collected = COALESCE(collected, 0) + p_amount, updated_at = now() WHERE id = p_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_group_collected(group_id uuid, amount double precision DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.group_contributions SET collected = COALESCE(collected, 0) + amount, updated_at = now() WHERE id = group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_klip_view(p_klip_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.klips SET views = COALESCE(views, 0) + 1 WHERE id = p_klip_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_study_attendees(p_study_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.bible_studies
  SET current_attendees = current_attendees + 1
  WHERE id = p_study_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.heartbeat_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.profiles SET last_seen = now() WHERE id = auth.uid();
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_validate_import_columns(p_table text, p_columns text[])
RETURNS TABLE(column_name text, valid boolean, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    forbidden TEXT[] := ARRAY[
        'role','coins','streak_count','balance_cc','balance_zmw',
        'is_work_mode','password_hash','email','created_at','updated_at'
    ];
    col TEXT;
BEGIN
    IF auth.uid() IS NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    FOREACH col IN ARRAY p_columns LOOP
        IF col = ANY(forbidden) THEN
            column_name := col; valid := false; reason := 'column is restricted (role/coins/balance escalation guard)';
            RETURN NEXT;
        ELSIF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = p_table AND column_name = col
        ) THEN
            column_name := col; valid := false; reason := 'column does not exist on ' || p_table;
            RETURN NEXT;
        ELSE
            column_name := col; valid := true; reason := '';
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;

-- ============================================================
-- REVOKE sweep: strip PUBLIC/anon from ALL remaining secdef functions
-- (increment_website_view intentionally keeps anon for public pages)
-- ============================================================
REVOKE ALL ON FUNCTION public.process_payroll(UUID, INTEGER, INTEGER, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_payroll(UUID, INTEGER, INTEGER, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.insert_transaction_idempotent(TEXT, UUID, UUID, DOUBLE PRECISION, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.insert_transaction_idempotent(TEXT, UUID, UUID, DOUBLE PRECISION, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.redeem_coins_atomic(UUID, INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_coins_atomic(UUID, INTEGER, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.reactivate_tenant(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reactivate_tenant(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.suspend_tenant(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suspend_tenant(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.toggle_system_freeze(BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_system_freeze(BOOLEAN, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.join_business_meeting(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_business_meeting(UUID, UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.start_business_meeting(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_business_meeting(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.record_event_checkin(UUID, UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_event_checkin(UUID, UUID, UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.get_organization_church_member_counts(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_church_member_counts(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_platform_engagement_stats(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_platform_engagement_stats(INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.get_streaming_usage(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_streaming_usage(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.record_streaming_minutes(UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_streaming_minutes(UUID, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.record_streaming_minutes(UUID, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_streaming_minutes(UUID, NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.record_streaming_minutes(UUID, NUMERIC, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_streaming_minutes(UUID, NUMERIC, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_settlement_phone(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_settlement_phone(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.award_xp(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_xp(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.next_id_sequence(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_id_sequence(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.increment_member_paid(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_member_paid(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_member_paid(UUID, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_member_paid(UUID, DOUBLE PRECISION) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_promo_redemption(TEXT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_promo_redemption(TEXT, NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_ad_impression(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_ad_impression(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_attendee_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_attendee_count(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_group_collected(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_group_collected(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_group_collected(UUID, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_group_collected(UUID, DOUBLE PRECISION) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_klip_view(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_klip_view(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_study_attendees(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_study_attendees(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.generate_meeting_code() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_meeting_code() TO authenticated;

REVOKE ALL ON FUNCTION public.heartbeat_presence() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_presence() TO authenticated;

REVOKE ALL ON FUNCTION public.sp_validate_import_columns(TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sp_validate_import_columns(TEXT, TEXT[]) TO authenticated, service_role;

-- Guarded read helpers / boolean checks used by RLS and app flows:
-- keep them for authenticated, drop anon/PUBLIC.
REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.is_church_pastor(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_church_pastor(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.is_church_trial_active(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_church_trial_active(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.is_system_locked() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_system_locked() TO authenticated;

REVOKE ALL ON FUNCTION public.user_has_feature_access(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_feature_access(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.get_subscription_pricing() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_pricing() TO authenticated;

REVOKE ALL ON FUNCTION public.process_tithe_and_ledger(UUID, UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_tithe_and_ledger(UUID, UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.check_role_change_permission(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_role_change_permission(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.update_subscription_pricing(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_subscription_pricing(JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.subscribe_user_to_tier(TEXT, TEXT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.subscribe_user_to_tier(TEXT, TEXT, NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.user_owns_order_items(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_owns_order_items(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.update_product_rating_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_product_rating_stats(UUID) TO authenticated;

-- Cron / maintenance functions: service_role only
REVOKE ALL ON FUNCTION public.cleanup_expired_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_sessions() TO service_role;

REVOKE ALL ON FUNCTION public.cleanup_old_login_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_old_login_history() TO service_role;

REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_rate_limits() TO service_role;

-- Trigger functions: no PUBLIC/anon (triggers fire internally; grants
-- only affect direct RPC calls, which we block for anon)
REVOKE ALL ON FUNCTION public.auto_create_notification_preferences() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auto_join_community_group() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ensure_tenant_on_church_insert() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.handle_marketplace_review_change() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.link_pre_registration() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.log_role_change_trigger() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.notify_profile_role_change() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.notify_role_approved() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.notify_writer_approved() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.profiles_tenant_sync() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.refresh_reporting_views() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reset_church_trial_on_approval() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_church_trial() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_message_sender_info() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_profile_coins() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_profile_role_to_app_metadata() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_sermon_reaction_counts() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_social_comments_count() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_social_likes_count() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.check_role_change_permission() FROM PUBLIC, anon;