-- ============================================================================
-- 20261266 — OPS COMMAND CENTRE (bishop rollup + threshold alerts + digest)
--
-- Turns the pastor/bishop dashboards from LOOK-AT-ME reporting into PUSH-TO-
-- LEADER operations:
--
--   1. get_org_care_signals(p_org_id) — the bishop-level exception rollup:
--      per branch, open follow-ups, absentee count, new visitors, last service
--      report date, giving and attendance month-over-month, and the reasons
--      that branch needs attention.
--   2. check_ops_thresholds() — daily cron: per active church, giving drop
--      >=40% MoM, attendance drop >=40% MoM, or no service report in 8 days
--      -> in-app notification (type 'ops_alert') to every owner-tier member.
--   3. send_weekly_ops_digest() — Monday 07:00 cron: last week's attendance,
--      giving, reporting compliance and care top-5 -> one 'ops_digest'
--      notification per owner-tier member.
--   4. ops_alert_log — dedup so an alert fires once per kind per period.
--
-- Cron jobs call the SECURITY DEFINER functions DIRECTLY (pg_cron runs as
-- postgres) — no Edge hop, no CRON_SECRET, unlike the streaming crons.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Dedup ledger
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ops_alert_log (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id  uuid NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  kind       text NOT NULL,
  period_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (church_id, kind, period_key)
);
ALTER TABLE public.ops_alert_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ops_alert_log FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Bishop-level exception rollup
--    Caller must be platform staff, the org's bishop, or leadership of a
--    branch church in the organisation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_org_care_signals(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_branch record;
  v_out jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT COALESCE(public.is_platform_staff(), false) THEN
    -- the org's bishop/apostle...
    IF NOT EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = p_org_id AND o.bishop_id = v_uid
    )
    -- ...or leadership of any branch church in the org
    AND NOT EXISTS (
      SELECT 1
        FROM public.churches c
        JOIN public.profiles p ON p.tenant_id = c.id::text
       WHERE c.organization_id = p_org_id
         AND p.id = v_uid
         AND public.is_owner_tier_role(p.role)
    ) THEN
      RAISE EXCEPTION 'not_authorised';
    END IF;
  END IF;

  FOR v_branch IN
    SELECT c.id, c.name
      FROM public.churches c
     WHERE c.organization_id = p_org_id
     ORDER BY c.name
  LOOP
    DECLARE
      v_open_fu   integer := 0;
      v_absent    integer := 0;
      v_visitors  integer := 0;
      v_last_rep  date := NULL;
      v_give_now  numeric := 0;
      v_give_prev numeric := 0;
      v_att_now   integer := 0;
      v_att_prev  integer := 0;
      v_reasons   text[] := '{}';
    BEGIN
      -- Open pastoral follow-ups
      SELECT count(*) INTO v_open_fu
        FROM public.pastoral_followups
       WHERE tenant_id = v_branch.id AND status = 'open';

      -- Absentees: members with no attendance in 21 days (or never seen),
      -- excluding leaders and brand-new profiles.
      SELECT count(*) INTO v_absent
        FROM public.profiles p
       WHERE p.tenant_id = v_branch.id::text
         AND p.role = 'member'
         AND p.created_at < now() - interval '30 days'
         AND NOT EXISTS (
           SELECT 1 FROM public.attendance_logs al
            WHERE al.tenant_id = p.tenant_id::uuid
              AND al.user_id = p.id
              AND al.check_in_time > now() - interval '21 days'
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.member_attendance ma
            WHERE ma.tenant_id = p.tenant_id
              AND ma.user_id = p.id
              AND ma.service_date > now() - interval '21 days'
         );

      -- New visitors in the last 30 days
      SELECT count(*) INTO v_visitors
        FROM public.profiles p
       WHERE p.tenant_id = v_branch.id::text
         AND p.visitor_status = 'new'
         AND p.created_at > now() - interval '30 days';

      -- Last service report
      SELECT max(service_date)::date INTO v_last_rep
        FROM public.service_reports
       WHERE tenant_id = v_branch.id;

      -- Giving MoM (same span as the pastor dashboard uses)
      SELECT
        COALESCE(SUM(CASE WHEN t.created_at >= date_trunc('month', now()) THEN t.amount END), 0),
        COALESCE(SUM(CASE WHEN t.created_at >= date_trunc('month', now()) - interval '1 month'
                           AND t.created_at < date_trunc('month', now())
                          THEN t.amount END), 0)
      INTO v_give_now, v_give_prev
      FROM public.transactions t
       WHERE t.tenant_id = v_branch.id
         AND t.status = 'completed'
         AND t.category IN ('giving','tithe','offering')
         AND t.created_at >= date_trunc('month', now()) - interval '1 month';

      -- Attendance MoM (distinct people)
      SELECT
        COUNT(DISTINCT CASE WHEN a.d >= date_trunc('month', now())::date THEN a.user_id END),
        COUNT(DISTINCT CASE WHEN a.d >= (date_trunc('month', now()) - interval '1 month')::date
                             AND a.d < date_trunc('month', now())::date THEN a.user_id END)
      INTO v_att_now, v_att_prev
      FROM (
        SELECT user_id, check_in_time::date AS d FROM public.attendance_logs
         WHERE tenant_id = v_branch.id
           AND check_in_time >= date_trunc('month', now()) - interval '1 month'
        UNION
        SELECT user_id, service_date AS d FROM public.member_attendance
         WHERE tenant_id = v_branch.id::text
           AND service_date >= (date_trunc('month', now()) - interval '1 month')::date
      ) a;

      IF v_open_fu > 0 THEN v_reasons := v_reasons || v_open_fu::text || ' open follow-ups'; END IF;
      IF v_absent > 0 THEN v_reasons := v_reasons || v_absent::text || ' members not seen in 21+ days'; END IF;
      IF v_visitors > 0 THEN v_reasons := v_reasons || v_visitors::text || ' new visitor(s) to welcome'; END IF;
      IF v_last_rep IS NULL OR v_last_rep < (now() - interval '8 days')::date
        THEN v_reasons := v_reasons || 'service report overdue'; END IF;
      IF v_give_prev >= 100 AND v_give_now < v_give_prev * 0.6
        THEN v_reasons := v_reasons || 'giving down ' || GREATEST(1, ROUND((1 - v_give_now / NULLIF(v_give_prev,0)) * 100))::text || '% MoM'; END IF;
      IF v_att_prev >= 10 AND v_att_now < v_att_prev * 0.6
        THEN v_reasons := v_reasons || 'attendance down ' || GREATEST(1, ROUND((1 - v_att_now / NULLIF(v_att_prev,0)) * 100))::text || '% MoM'; END IF;

      v_out := v_out || jsonb_build_object(
        'church_id', v_branch.id,
        'name', v_branch.name,
        'open_followups', v_open_fu,
        'absentees', v_absent,
        'new_visitors', v_visitors,
        'last_report_date', v_last_rep,
        'giving_mtd', v_give_now,
        'giving_prev_month', v_give_prev,
        'attendance_mtd', v_att_now,
        'attendance_prev_month', v_att_prev,
        'attention', array_to_string(v_reasons, '; ')
      );
    END;
  END LOOP;

  RETURN v_out;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_org_care_signals(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_care_signals(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Recipients: every owner-tier member of a church
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.ops_recipients(p_church_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id
    FROM public.profiles p
   WHERE p.tenant_id = p_church_id::text
     AND public.is_owner_tier_role(p.role);
$$;

-- ---------------------------------------------------------------------------
-- 4. Daily threshold alerts
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_ops_thresholds()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church record;
  v_sent integer := 0;
  v_give_now numeric := 0;
  v_give_prev numeric := 0;
  v_att_now integer := 0;
  v_att_prev integer := 0;
  v_last_rep date := NULL;
  v_period text := to_char(now(), 'YYYY-MM');
  v_recipient uuid;
BEGIN
  FOR v_church IN
    SELECT c.id, c.name
      FROM public.churches c
     WHERE c.is_verified = true
  LOOP
    -- Giving MoM
    SELECT
      COALESCE(SUM(CASE WHEN t.created_at >= date_trunc('month', now()) THEN t.amount END), 0),
      COALESCE(SUM(CASE WHEN t.created_at >= date_trunc('month', now()) - interval '1 month'
                         AND t.created_at < date_trunc('month', now()) THEN t.amount END), 0)
    INTO v_give_now, v_give_prev
    FROM public.transactions t
     WHERE t.tenant_id = v_church.id
       AND t.status = 'completed'
       AND t.category IN ('giving','tithe','offering')
       AND t.created_at >= date_trunc('month', now()) - interval '1 month';

    IF v_give_prev >= 100 AND v_give_now < v_give_prev * 0.6
       AND NOT EXISTS (SELECT 1 FROM public.ops_alert_log
                        WHERE church_id = v_church.id AND kind = 'giving_drop' AND period_key = v_period) THEN
      INSERT INTO public.ops_alert_log (church_id, kind, period_key)
      VALUES (v_church.id, 'giving_drop', v_period);
      FOR v_recipient IN SELECT * FROM private.ops_recipients(v_church.id) LOOP
        INSERT INTO public.notifications (user_id, tenant_id, church_id, title, body, is_read, type, reference_id)
        VALUES (v_recipient, v_church.id, v_church.id,
          'Giving alert — ' || v_church.name,
          'Giving this month is down ' || GREATEST(1, ROUND((1 - v_give_now / NULLIF(v_give_prev, 0)) * 100))::text ||
          '% vs last month (K' || ROUND(v_give_prev)::text || ' -> K' || ROUND(v_give_now)::text || '). Open the finance dashboard to see where.',
          false, 'ops_alert', v_church.id::text);
        v_sent := v_sent + 1;
      END LOOP;
    END IF;

    -- Attendance MoM (distinct people)
    SELECT
      COUNT(DISTINCT CASE WHEN a.d >= date_trunc('month', now())::date THEN a.user_id END),
      COUNT(DISTINCT CASE WHEN a.d >= (date_trunc('month', now()) - interval '1 month')::date
                           AND a.d < date_trunc('month', now())::date THEN a.user_id END)
    INTO v_att_now, v_att_prev
    FROM (
      SELECT user_id, check_in_time::date AS d FROM public.attendance_logs
       WHERE tenant_id = v_church.id
         AND check_in_time >= date_trunc('month', now()) - interval '1 month'
      UNION
      SELECT user_id, service_date AS d FROM public.member_attendance
       WHERE tenant_id = v_church.id::text
         AND service_date >= (date_trunc('month', now()) - interval '1 month')::date
    ) a;

    IF v_att_prev >= 10 AND v_att_now < v_att_prev * 0.6
       AND NOT EXISTS (SELECT 1 FROM public.ops_alert_log
                        WHERE church_id = v_church.id AND kind = 'attendance_drop' AND period_key = v_period) THEN
      INSERT INTO public.ops_alert_log (church_id, kind, period_key)
      VALUES (v_church.id, 'attendance_drop', v_period);
      FOR v_recipient IN SELECT * FROM private.ops_recipients(v_church.id) LOOP
        INSERT INTO public.notifications (user_id, tenant_id, church_id, title, body, is_read, type, reference_id)
        VALUES (v_recipient, v_church.id, v_church.id,
          'Attendance alert — ' || v_church.name,
          'Attendance this month (' || v_att_now || ') is down ' ||
          GREATEST(1, ROUND((1 - v_att_now / NULLIF(v_att_prev, 0)) * 100))::text ||
          '% vs last month (' || v_att_prev || '). The care queue lists who to visit.',
          false, 'ops_alert', v_church.id::text);
        v_sent := v_sent + 1;
      END LOOP;
    END IF;

    -- Missing service report
    SELECT max(service_date)::date INTO v_last_rep
      FROM public.service_reports
     WHERE tenant_id = v_church.id;

    IF (v_last_rep IS NULL OR v_last_rep < (now() - interval '8 days')::date)
       AND NOT EXISTS (SELECT 1 FROM public.ops_alert_log
                        WHERE church_id = v_church.id AND kind = 'missing_report' AND period_key = v_period) THEN
      INSERT INTO public.ops_alert_log (church_id, kind, period_key)
      VALUES (v_church.id, 'missing_report', v_period);
      FOR v_recipient IN SELECT * FROM private.ops_recipients(v_church.id) LOOP
        INSERT INTO public.notifications (user_id, tenant_id, church_id, title, body, is_read, type, reference_id)
        VALUES (v_recipient, v_church.id, v_church.id,
          'Service report overdue — ' || v_church.name,
          CASE WHEN v_last_rep IS NULL
            THEN 'No service report has ever been filed. File one after the next service so the network sees your branch.'
            ELSE 'The last service report was ' || (now()::date - v_last_rep) || ' days ago. File this week''s report to keep the network dashboard current.' END,
          false, 'ops_alert', v_church.id::text);
        v_sent := v_sent + 1;
      END LOOP;
    END IF;
  END LOOP;

  RETURN v_sent;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_ops_thresholds() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Weekly ops digest (Monday 07:00)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_weekly_ops_digest()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_church record;
  v_sent integer := 0;
  v_week_start date := (date_trunc('week', now() - interval '7 days'))::date;
  v_week_end date := v_week_start + 6;
  v_period text := to_char(v_week_start, 'IYYY-"W"IW');
  v_att integer := 0;
  v_give numeric := 0;
  v_rep boolean := false;
  v_absent integer := 0;
  v_body text;
  v_recipient uuid;
BEGIN
  FOR v_church IN
    SELECT c.id, c.name
      FROM public.churches c
     WHERE c.is_verified = true
  LOOP
    IF EXISTS (SELECT 1 FROM public.ops_alert_log
                WHERE church_id = v_church.id AND kind = 'weekly_digest' AND period_key = v_period) THEN
      CONTINUE;
    END IF;

    SELECT COUNT(DISTINCT al.user_id) INTO v_att
      FROM public.attendance_logs al
     WHERE al.tenant_id = v_church.id
       AND al.check_in_time::date BETWEEN v_week_start AND v_week_end;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_give
      FROM public.transactions t
     WHERE t.tenant_id = v_church.id
       AND t.status = 'completed'
       AND t.category IN ('giving','tithe','offering')
       AND t.created_at::date BETWEEN v_week_start AND v_week_end;

    SELECT EXISTS (SELECT 1 FROM public.service_reports sr
                    WHERE sr.tenant_id = v_church.id
                      AND sr.service_date BETWEEN v_week_start AND v_week_end) INTO v_rep;

    SELECT count(*) INTO v_absent
      FROM public.profiles p
     WHERE p.tenant_id = v_church.id::text
       AND p.role = 'member'
       AND p.created_at < now() - interval '30 days'
       AND NOT EXISTS (SELECT 1 FROM public.attendance_logs al
                        WHERE al.tenant_id = p.tenant_id::uuid AND al.user_id = p.id
                          AND al.check_in_time > now() - interval '21 days')
       AND NOT EXISTS (SELECT 1 FROM public.member_attendance ma
                        WHERE ma.tenant_id = p.tenant_id AND ma.user_id = p.id
                          AND ma.service_date > now() - interval '21 days');

    v_body := 'Last week (' || v_week_start || ' to ' || v_week_end || '): ' ||
              v_att || ' people attended, K' || ROUND(v_give)::text || ' given, ' ||
              CASE WHEN v_rep THEN 'service report filed' ELSE 'NO service report filed' END ||
              ', ' || v_absent || ' member(s) not seen in 21+ days. Open the dashboard for the care queue.';

    INSERT INTO public.ops_alert_log (church_id, kind, period_key)
    VALUES (v_church.id, 'weekly_digest', v_period);

    FOR v_recipient IN SELECT * FROM private.ops_recipients(v_church.id) LOOP
      INSERT INTO public.notifications (user_id, tenant_id, church_id, title, body, is_read, type, reference_id)
      VALUES (v_recipient, v_church.id, v_church.id,
        'Weekly Ops Digest — ' || v_church.name,
        v_body, false, 'ops_digest', v_church.id::text);
      v_sent := v_sent + 1;
    END LOOP;
  END LOOP;

  RETURN v_sent;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_weekly_ops_digest() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Cron (direct function calls — no Edge hop, no secret)
-- ---------------------------------------------------------------------------
SELECT cron.unschedule('ops-threshold-alerts')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ops-threshold-alerts');
SELECT cron.schedule('ops-threshold-alerts', '30 6 * * *',
  $$SELECT public.check_ops_thresholds();$$);

SELECT cron.unschedule('ops-weekly-digest')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ops-weekly-digest');
SELECT cron.schedule('ops-weekly-digest', '0 7 * * 1',
  $$SELECT public.send_weekly_ops_digest();$$);

-- ---------------------------------------------------------------------------
-- 7. Verification
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_fail text := '';
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proname IN ('get_org_care_signals','check_ops_thresholds','send_weekly_ops_digest','ops_recipients')) <> 4 THEN
    v_fail := v_fail || ' functions;';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'ops_alert_log') THEN
    v_fail := v_fail || ' log_table;';
  END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobname IN ('ops-threshold-alerts','ops-weekly-digest')) <> 2 THEN
    v_fail := v_fail || ' cron;';
  END IF;
  IF v_fail <> '' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED:%', v_fail;
  END IF;
  RAISE NOTICE 'ops command centre deployed';
END;
$$;
