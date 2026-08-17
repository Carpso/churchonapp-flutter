-- 20260907 — SECURITY HARDENING ROUND 2 (full DB audit, 2026-08-17)
--
-- Fixes SECURITY DEFINER functions that were executable by anon/PUBLIC
-- and/or trusted client-supplied identity arguments. All fixes verified
-- against the LIVE database (pg_proc.proacl + bodies) before writing this.
--
-- 1. award_user_coins / award_user_xp     — CRITICAL: anon+PUBLIC could mint
--    unlimited coins/XP for ANY user (no auth check at all).
-- 2. enqueue_church_auto_payouts          — CRITICAL: any authenticated user
--    could enqueue REAL payout tasks for every eligible church.
-- 3. _church_withdrawable_balances_svc    — authenticated had EXECUTE on the
--    service-only balance core (no guard) -> any user could read every
--    church's withdrawable balance.
-- 4. get_filtered_tithe_records (5-arg)   — CRITICAL: no auth guard -> anyone
--    could read ANY user's tithe records (financial data). 4-arg overload
--    already guarded.
-- 5. get_organization_stats / get_node_aggregated_stats — anon could read
--    member counts + giving sums for any org/node.
-- 6. get_church_service_summary / get_organization_service_summary — anon
--    could read attendance/offering for any church/org.
-- 7. get_coa_payment_stats                — anon could read COA financial stats.
-- 8. end_business_meeting                 — trusted client-supplied p_user_id;
--    anyone could pass the host UUID and end any meeting.
-- 9. extend_church_trial                  — only checked auth.uid() != NULL:
--    ANY logged-in user could extend ANY church's trial + mark verified
--    (subscription/verification bypass).
-- 10. create_weekly_quiz_season           — anon could deactivate the active
--    season and mint new ones (DoS).
-- 11. generate_tenant_code / check_admin_rate_limit / calculate_paye /
--    get_my_tenant_id                     — anon-executable hygiene.
-- 12. get_church_withdrawable_balances / get_church_withdrawals — role-guarded
--    but NOT tenant-scoped: any treasurer/pastor/bishop saw ALL churches'
--    balances + history.
--
-- After this migration the only intentionally anon-executable SECURITY
-- DEFINER functions are: increment_website_view (public view counter,
-- guarded to is_published), is_admin_or_employee (returns boolean), and
-- trigger functions (invoked internally by triggers).

-- ============================================================
-- 1. award_user_coins / award_user_xp — add authz, ignore client granter
-- ============================================================
CREATE OR REPLACE FUNCTION public.award_user_coins(
    target_user_id TEXT,
    coin_amount INTEGER,
    reason_title TEXT DEFAULT 'Reward',
    reason_desc TEXT DEFAULT '',
    granter_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_granter UUID := auth.uid();
BEGIN
    IF v_granter IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_granter AND role IN ('superadmin', 'coa_employee', 'employee'))
    THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    IF coin_amount IS NULL OR coin_amount <= 0 OR coin_amount > 100000 THEN
        RAISE EXCEPTION 'Invalid coin amount';
    END IF;
    UPDATE public.profiles
    SET coins = COALESCE(coins, 0) + coin_amount
    WHERE id = target_user_id::UUID;

    INSERT INTO public.user_rewards (user_id, reward_type, amount, title, description, granted_by)
    VALUES (target_user_id::UUID, 'coins', coin_amount, reason_title, reason_desc, v_granter);
END;
$$;

CREATE OR REPLACE FUNCTION public.award_user_xp(
    target_user_id TEXT,
    xp_amount INTEGER,
    reason_title TEXT DEFAULT 'XP Reward',
    reason_desc TEXT DEFAULT '',
    granter_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_granter UUID := auth.uid();
BEGIN
    IF v_granter IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_granter AND role IN ('superadmin', 'coa_employee', 'employee'))
    THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    IF xp_amount IS NULL OR xp_amount <= 0 OR xp_amount > 100000 THEN
        RAISE EXCEPTION 'Invalid XP amount';
    END IF;
    UPDATE public.profiles
    SET xp = COALESCE(xp, 0) + xp_amount
    WHERE id = target_user_id::UUID;

    INSERT INTO public.user_rewards (user_id, reward_type, amount, title, description, granted_by)
    VALUES (target_user_id::UUID, 'xp', xp_amount, reason_title, reason_desc, v_granter);
END;
$$;

-- ============================================================
-- 2. enqueue_church_auto_payouts — service_role only
-- ============================================================
CREATE OR REPLACE FUNCTION public.enqueue_church_auto_payouts(p_min_kwacha numeric DEFAULT 100)
RETURNS TABLE(church_id text, church_name text, withdrawal_id uuid, task_id uuid, gross_amount numeric, recipient_phone text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_min NUMERIC := GREATEST(COALESCE(p_min_kwacha, 100), 0); rec RECORD; v_withdrawal_id UUID; v_task_id UUID;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Not authorized'; -- service role only (cron / webhook)
    END IF;
    FOR rec IN SELECT * FROM public._church_withdrawable_balances_svc() WHERE withdrawable >= v_min LOOP
        BEGIN
            INSERT INTO public.church_withdrawals (church_id, church_name, gross_amount, recipient_phone, status)
            VALUES (rec.church_id, rec.church_name, rec.withdrawable, rec.treasurer_phone, 'pending')
            RETURNING id INTO v_withdrawal_id;
            INSERT INTO public.payout_tasks (source, source_ref, payment_ref, user_id, recipient_phone, gross_amount, status)
            VALUES ('church_payout', v_withdrawal_id::text, NULL, NULL, rec.treasurer_phone, rec.withdrawable, 'pending')
            RETURNING id INTO v_task_id;
            church_id := rec.church_id; church_name := rec.church_name; withdrawal_id := v_withdrawal_id;
            task_id := v_task_id; gross_amount := rec.withdrawable; recipient_phone := rec.treasurer_phone;
            RETURN NEXT;
        EXCEPTION WHEN unique_violation THEN
            NULL; -- another enqueue already created this church's in-flight withdrawal
        END;
    END LOOP;
    RETURN;
END;
$function$;

-- ============================================================
-- 3. _church_withdrawable_balances_svc — service role only
-- ============================================================
CREATE OR REPLACE FUNCTION public._church_withdrawable_balances_svc()
RETURNS TABLE(church_id text, church_name text, treasurer_phone text, gross_collected numeric, committed_giving numeric, in_flight_withdrawals numeric, withdrawable numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    -- No auth check inside: EXECUTE is revoked from anon/authenticated/PUBLIC
    -- (service_role only). Authenticated callers reach it through the
    -- role-gated + tenant-scoped wrappers (get_church_withdrawable_balances /
    -- get_church_withdrawals), which run as the owner and call this core.
    RETURN QUERY
    WITH confirmed AS (
        SELECT metadata->>'tenant_id' AS tenant_id, COALESCE(amount, 0) AS amount
        FROM public.coa_payments
        WHERE status IN ('approved', 'completed', 'confirmed', 'settled')
          AND metadata->>'tenant_id' IS NOT NULL
    ),
    committed AS (
        SELECT source_ref AS tenant_id, COALESCE(gross_amount, 0) AS amount
        FROM public.payout_tasks
        WHERE source IN ('giving', 'church_payout')
          AND status IN ('pending', 'processing', 'paid')
    ),
    in_flight AS (
        SELECT church_id AS tenant_id, COALESCE(gross_amount, 0) AS amount
        FROM public.church_withdrawals
        WHERE status IN ('pending', 'processing')
    ),
    gross AS (SELECT tenant_id, SUM(amount) AS total FROM confirmed GROUP BY tenant_id),
    committed_totals AS (SELECT tenant_id, SUM(amount) AS total FROM committed GROUP BY tenant_id),
    in_flight_totals AS (SELECT tenant_id, SUM(amount) AS total FROM in_flight GROUP BY tenant_id)
    SELECT
        g.tenant_id,
        COALESCE(ch.name, 'Unknown Church') AS church_name,
        COALESCE(pr.phone, '') AS treasurer_phone,
        g.total AS gross_collected,
        COALESCE(ct.total, 0) AS committed_giving,
        COALESCE(ift.total, 0) AS in_flight_withdrawals,
        g.total - COALESCE(ct.total, 0) - COALESCE(ift.total, 0) AS withdrawable
    FROM gross g
    LEFT JOIN public.churches ch ON ch.id::text = g.tenant_id
    LEFT JOIN LATERAL (
        SELECT phone FROM public.profiles
        WHERE tenant_id = g.tenant_id AND role = 'treasurer' ORDER BY created_at LIMIT 1
    ) pr ON true
    WHERE g.total - COALESCE(ct.total, 0) - COALESCE(ift.total, 0) > 0
    ORDER BY withdrawable DESC;
END;
$function$;

-- ============================================================
-- 4. get_filtered_tithe_records (5-arg) — same guard as 4-arg
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_filtered_tithe_records(p_user_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_min_amount double precision DEFAULT NULL::double precision, p_max_amount double precision DEFAULT NULL::double precision)
RETURNS TABLE(id uuid, amount double precision, currency text, given_at timestamp with time zone, payment_method text, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS DISTINCT FROM p_user_id AND auth.role() <> 'service_role' AND NOT EXISTS (
        SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin','pastor','bishop','general_treasurer','general_secretary','superadmin','employee')
    ) THEN
        RAISE EXCEPTION 'Not authorized to view this user''s tithe records';
    END IF;
    RETURN QUERY
    SELECT t.id, t.amount, COALESCE(t.currency, 'ZMW') AS currency, t.given_at, t.payment_method, COALESCE(t.status, 'confirmed') AS status
    FROM public.tithes t
    WHERE t.user_id = p_user_id
      AND (p_start_date IS NULL OR t.given_at >= p_start_date)
      AND (p_end_date IS NULL OR t.given_at <= p_end_date)
      AND (p_min_amount IS NULL OR t.amount >= p_min_amount)
      AND (p_max_amount IS NULL OR t.amount <= p_max_amount)
    ORDER BY t.given_at DESC;
END;
$function$;

-- ============================================================
-- 5. get_organization_stats / get_node_aggregated_stats
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_organization_stats(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_member_count BIGINT; v_branch_count BIGINT; v_total_giving NUMERIC; v_active_streams BIGINT;
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = p_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*) INTO v_member_count FROM public.profiles p JOIN public.churches c ON c.id = p.tenant_id WHERE c.organization_id = p_org_id;
    SELECT COUNT(*) INTO v_branch_count FROM public.churches WHERE organization_id = p_org_id;
    SELECT COALESCE(SUM(amount), 0) INTO v_total_giving FROM public.transactions t JOIN public.churches c ON c.id = t.tenant_id WHERE c.organization_id = p_org_id AND t.status = 'settled' AND t.created_at >= date_trunc('month', now());
    SELECT COUNT(*) INTO v_active_streams FROM public.live_streams ls JOIN public.churches c ON c.id = ls.church_id WHERE c.organization_id = p_org_id AND ls.status = 'live';
    RETURN jsonb_build_object('members', v_member_count, 'branches', v_branch_count, 'monthly_giving', v_total_giving, 'active_streams', v_active_streams);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_node_aggregated_stats(p_node_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_total_attendance BIGINT := 0; v_total_giving NUMERIC := 0; v_branch_count BIGINT := 0; v_child_nodes UUID[];
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND EXISTS (
                  SELECT 1 FROM public.hierarchy_nodes hn
                  JOIN public.churches nc ON nc.id::text = hn.tenant_id
                  WHERE hn.id = p_node_id AND nc.organization_id = my_c.organization_id
              )
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    WITH RECURSIVE tree AS (
        SELECT id, tenant_id FROM hierarchy_nodes WHERE id = p_node_id
        UNION ALL
        SELECT hn.id, hn.tenant_id FROM hierarchy_nodes hn JOIN tree t ON hn.parent_node_id = t.id
    )
    SELECT ARRAY_AGG(id) INTO v_child_nodes FROM tree WHERE tenant_id IS NOT NULL;
    IF v_child_nodes IS NOT NULL THEN
        SELECT COUNT(*) INTO v_branch_count FROM hierarchy_nodes WHERE id = ANY(v_child_nodes);
        SELECT COUNT(*) INTO v_total_attendance FROM attendance_logs al JOIN hierarchy_nodes hn ON hn.tenant_id::text = al.tenant_id::text WHERE hn.id = ANY(v_child_nodes) AND al.created_at >= date_trunc('month', now());
        SELECT COALESCE(SUM(amount), 0) INTO v_total_giving FROM transactions t JOIN hierarchy_nodes hn ON hn.tenant_id::text = t.tenant_id::text WHERE hn.id = ANY(v_child_nodes) AND t.status = 'settled' AND t.created_at >= date_trunc('month', now());
    END IF;
    RETURN jsonb_build_object('branches', v_branch_count, 'attendance', v_total_attendance, 'giving', v_total_giving);
END;
$function$;

-- ============================================================
-- 6. get_church_service_summary / get_organization_service_summary
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_church_service_summary(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_service_count INT; v_total_attendance INT; v_total_offering NUMERIC; v_total_visitors INT; v_total_salvations INT; v_total_online_viewers INT; v_month_start DATE := date_trunc('month', now())::date;
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR (auth.uid() IS NOT NULL AND get_my_tenant_id()::uuid = p_tenant_id
            AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin','pastor','bishop','general_secretary','general_treasurer','treasurer')))
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*), COALESCE(SUM(attendance), 0), COALESCE(SUM(offering), 0), COALESCE(SUM(visitors), 0), COALESCE(SUM(salvations), 0), COALESCE(SUM(online_viewers), 0)
    INTO v_service_count, v_total_attendance, v_total_offering, v_total_visitors, v_total_salvations, v_total_online_viewers
    FROM public.service_reports
    WHERE tenant_id = p_tenant_id::text AND (service_date >= v_month_start OR service_date IS NULL) AND created_at >= v_month_start;
    RETURN jsonb_build_object('service_count', v_service_count, 'attendance', v_total_attendance, 'offering', v_total_offering, 'visitors', v_total_visitors, 'salvations', v_total_salvations, 'online_viewers', v_total_online_viewers);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_organization_service_summary(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_service_count INT; v_total_attendance INT; v_total_offering NUMERIC; v_total_visitors INT; v_total_salvations INT; v_total_online_viewers INT; v_church_count INT; v_month_start DATE := date_trunc('month', now())::date;
BEGIN
    IF NOT (
        is_admin_or_employee()
        OR EXISTS (
            SELECT 1 FROM public.profiles me
            JOIN public.churches my_c ON my_c.id::text = me.tenant_id
            WHERE me.id = auth.uid() AND me.role IN ('apostle','bishop','general_secretary','pastor','admin')
              AND my_c.organization_id = p_org_id
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*) INTO v_church_count FROM public.churches WHERE organization_id = p_org_id;
    SELECT COUNT(*), COALESCE(SUM(sr.attendance), 0), COALESCE(SUM(sr.offering), 0), COALESCE(SUM(sr.visitors), 0), COALESCE(SUM(sr.salvations), 0), COALESCE(SUM(sr.online_viewers), 0)
    INTO v_service_count, v_total_attendance, v_total_offering, v_total_visitors, v_total_salvations, v_total_online_viewers
    FROM public.service_reports sr JOIN public.churches c ON c.id::text = sr.tenant_id
    WHERE c.organization_id = p_org_id AND (sr.service_date >= v_month_start OR sr.service_date IS NULL) AND sr.created_at >= v_month_start;
    RETURN jsonb_build_object('churches', v_church_count, 'service_count', v_service_count, 'attendance', v_total_attendance, 'offering', v_total_offering, 'visitors', v_total_visitors, 'salvations', v_total_salvations, 'online_viewers', v_total_online_viewers);
END;
$function$;

-- ============================================================
-- 7. get_coa_payment_stats
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_coa_payment_stats(p_today text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_pending_count BIGINT; v_pending_amount NUMERIC; v_settled_today_count BIGINT; v_settled_today_amount NUMERIC; v_failed_count BIGINT; v_failed_amount NUMERIC; v_mtn_amount NUMERIC; v_airtel_amount NUMERIC; v_zamtel_amount NUMERIC;
BEGIN
    IF NOT is_admin_or_employee() THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_pending_count, v_pending_amount FROM public.coa_payments WHERE status = 'pending';
    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_settled_today_count, v_settled_today_amount FROM public.coa_payments WHERE status = 'settled' AND settled_at::text >= p_today;
    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_failed_count, v_failed_amount FROM public.coa_payments WHERE status = 'failed';
    SELECT COALESCE(SUM(amount), 0) INTO v_mtn_amount FROM public.coa_payments WHERE network = 'MTN' AND status = 'settled';
    SELECT COALESCE(SUM(amount), 0) INTO v_airtel_amount FROM public.coa_payments WHERE network = 'Airtel' AND status = 'settled';
    SELECT COALESCE(SUM(amount), 0) INTO v_zamtel_amount FROM public.coa_payments WHERE network = 'Zamtel' AND status = 'settled';
    RETURN jsonb_build_object('pending_count', v_pending_count, 'pending_amount', v_pending_amount, 'settled_today_count', v_settled_today_count, 'settled_today_amount', v_settled_today_amount, 'failed_count', v_failed_count, 'failed_amount', v_failed_amount, 'mtn_amount', v_mtn_amount, 'airtel_amount', v_airtel_amount, 'zamtel_amount', v_zamtel_amount);
END;
$function$;

-- ============================================================
-- 8. end_business_meeting — use auth.uid(), never client-supplied identity
-- ============================================================
CREATE OR REPLACE FUNCTION public.end_business_meeting(p_meeting_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_meeting RECORD; v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
    END IF;
    SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
    END IF;
    IF v_meeting.host_id != v_uid THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only the host can end the meeting');
    END IF;
    UPDATE public.business_meetings SET status = 'ended', ended_at = now() WHERE id = p_meeting_id;
    UPDATE public.meeting_participants SET left_at = now() WHERE meeting_id = p_meeting_id AND left_at IS NULL;
    RETURN jsonb_build_object('success', true);
END;
$function$;

-- ============================================================
-- 9. extend_church_trial — require platform role
-- ============================================================
CREATE OR REPLACE FUNCTION public.extend_church_trial(p_church_id uuid, p_extra_days integer DEFAULT 30)
RETURNS timestamp with time zone
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_new_end TIMESTAMPTZ; v_admin_id UUID := auth.uid();
BEGIN
    IF v_admin_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role IN ('superadmin', 'coa_employee', 'employee')) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;
    UPDATE public.churches SET trial_ends_at = COALESCE(trial_ends_at, now()) + (p_extra_days || ' days')::interval, is_verified = true, verified_at = COALESCE(verified_at, now())
    WHERE id = p_church_id RETURNING trial_ends_at INTO v_new_end;
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
    VALUES (v_admin_id, 'church_trial_extended', 'churches', p_church_id, jsonb_build_object('extra_days', p_extra_days, 'new_end', v_new_end::TEXT));
    RETURN v_new_end;
END;
$function$;

-- ============================================================
-- 10. create_weekly_quiz_season — service role only (cron)
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_weekly_quiz_season()
RETURNS quiz_seasons
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_last_season quiz_seasons; v_new_week INT; v_season quiz_seasons;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Not authorized'; -- cron / service role only
    END IF;
    SELECT * INTO v_last_season FROM quiz_seasons ORDER BY end_date DESC LIMIT 1;
    v_new_week := COALESCE(v_last_season.week_number, 0) + 1;
    UPDATE quiz_seasons SET is_active = false WHERE is_active = true;
    INSERT INTO quiz_seasons (season_name, week_number, start_date, end_date, is_active)
    VALUES ('Week ' || v_new_week, v_new_week, date_trunc('week', now()), date_trunc('week', now()) + interval '6 days 23:59:59', true)
    RETURNING * INTO v_season;
    INSERT INTO quiz_season_rewards (season_id, rank_from, rank_to, reward_type, reward_value, reward_label) VALUES
    (v_season.id, 1, 1, 'zmw', 500, 'K500'),
    (v_season.id, 2, 2, 'zmw', 300, 'K300'),
    (v_season.id, 3, 3, 'zmw', 150, 'K150'),
    (v_season.id, 4, 10, 'coins', 100, '100 Coins');
    RETURN v_season;
END;
$function$;

-- ============================================================
-- 11. generate_tenant_code — authenticated/employee only
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_tenant_code(p_country text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_iso TEXT; v_seq TEXT; v_code TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    v_iso := CASE WHEN p_country ILIKE '%zambia%' THEN 'ZM' WHEN p_country ILIKE '%zimbabwe%' THEN 'ZW' WHEN p_country ILIKE '%kenya%' THEN 'KE' ELSE 'ZM' END;
    v_seq := public.next_id_sequence('tenant_code');
    v_code := 'COA-' || v_iso || '_T_' || v_seq;
    RETURN v_code;
END;
$function$;

-- ============================================================
-- 12. check_admin_rate_limit — block anon (both overloads)
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(admin_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE recent_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN RETURN true; END IF;
    SELECT COUNT(*) INTO recent_count FROM public.admin_audit_log WHERE admin_id = check_admin_rate_limit.admin_id AND created_at > now() - INTERVAL '1 minute';
    RETURN recent_count < 30;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(p_admin_id uuid, p_action_type text, p_max_requests integer DEFAULT 30, p_window_minutes integer DEFAULT 1)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN RETURN true; END IF;
    SELECT count(*) INTO v_count FROM public.admin_rate_limits WHERE admin_id = p_admin_id AND action_type = p_action_type AND created_at > now() - (p_window_minutes || ' minutes')::interval;
    IF v_count >= p_max_requests THEN RETURN false; END IF;
    INSERT INTO public.admin_rate_limits (admin_id, action_type) VALUES (p_admin_id, p_action_type);
    RETURN true;
END;
$function$;

-- ============================================================
-- 12b. Tenant-scope church payout reads for church roles
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_church_withdrawable_balances()
RETURNS TABLE(church_id text, church_name text, treasurer_phone text, gross_collected numeric, committed_giving numeric, in_flight_withdrawals numeric, withdrawable numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_role TEXT; v_tenant TEXT;
BEGIN
    SELECT p.role, p.tenant_id INTO v_role, v_tenant FROM public.profiles p WHERE p.id = auth.uid();
    IF v_role IS NULL THEN RETURN; END IF;
    IF v_role IN ('superadmin','employee','coa_employee') THEN
        RETURN QUERY SELECT * FROM public._church_withdrawable_balances_svc();
    ELSIF v_role IN ('treasurer','pastor','bishop') AND v_tenant IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public._church_withdrawable_balances_svc() WHERE church_id = v_tenant;
    END IF;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_church_withdrawals(p_limit integer DEFAULT 100)
RETURNS SETOF church_withdrawals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_role TEXT; v_tenant TEXT;
BEGIN
    SELECT p.role, p.tenant_id INTO v_role, v_tenant FROM public.profiles p WHERE p.id = auth.uid();
    IF v_role IS NULL THEN RETURN; END IF;
    IF v_role IN ('superadmin','employee','coa_employee') THEN
        RETURN QUERY SELECT * FROM public.church_withdrawals ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(p_limit, 500));
    ELSIF v_role IN ('treasurer','pastor','bishop') AND v_tenant IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.church_withdrawals WHERE church_id = v_tenant ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(p_limit, 500));
    END IF;
    RETURN;
END;
$function$;

-- ============================================================
-- REVOKES — strip anon / PUBLIC / (where required) authenticated
-- ============================================================
REVOKE ALL ON FUNCTION public.award_user_coins(TEXT, INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_user_coins(TEXT, INTEGER, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.award_user_xp(TEXT, INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_user_xp(TEXT, INTEGER, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_church_auto_payouts(NUMERIC) TO service_role;

REVOKE ALL ON FUNCTION public._church_withdrawable_balances_svc() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._church_withdrawable_balances_svc() TO service_role;

REVOKE ALL ON FUNCTION public.get_filtered_tithe_records(UUID, TIMESTAMPTZ, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_filtered_tithe_records(UUID, TIMESTAMPTZ, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

REVOKE ALL ON FUNCTION public.get_organization_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_stats(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_node_aggregated_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_node_aggregated_stats(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_church_service_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_service_summary(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_organization_service_summary(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_service_summary(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_coa_payment_stats(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_coa_payment_stats(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.end_business_meeting(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_business_meeting(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.extend_church_trial(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extend_church_trial(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.create_weekly_quiz_season() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_weekly_quiz_season() TO service_role;

REVOKE ALL ON FUNCTION public.generate_tenant_code(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_tenant_code(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.check_admin_rate_limit(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_admin_rate_limit(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.check_admin_rate_limit(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_admin_rate_limit(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.calculate_paye(NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_paye(NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_tenant_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_tenant_id() TO authenticated, service_role;
