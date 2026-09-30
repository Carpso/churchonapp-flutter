-- ═══════════════════════════════════════════════════════════════════════════
-- 20261236 — PASTORAL CARE, HOUSEHOLDS, ORDER OF SERVICE, VOLUNTEER ROTA
-- ═══════════════════════════════════════════════════════════════════════════
-- Implements the ChMS patterns worth copying for local-church management:
--
--   1. Auto-created pastoral follow-up the moment a person is FIRST marked
--      as a visitor (Breeze / Planning Center behaviour) — trigger, not UI.
--   2. Households (families) as the unit of care + household giving envelope.
--   4. "People to see today" — one RPC over four signals:
--         due follow-ups | visitors in their 2nd week
--         | absent 4+ weeks | un-baptised 3+ months
--   5. service_plans — order-of-service lite (songs, speakers, ushers,
--      publish-to-congregation toggle).
--   6. Attendance automations (3 visits/4 weeks, baptism confirmation).
--  11. Auto-tag regular attenders (>= N services in M months).
--  12. Scoped delegate permissions for ushers/deacons.
--
-- TYPE NOTES (verified against live DB — do not "simplify" these):
--   profiles.tenant_id               = TEXT
--   profiles.tenant_id_uuid          = UUID
--   pastoral_followups.tenant_id     = UUID
--   member_attendance.tenant_id      = TEXT
--   attendance_logs.tenant_id        = UUID
--   service_reports.tenant_id        = UUID
-- ───────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════
-- 0. LEADERSHIP HELPER
--     No `is_tenant_leadership()` existed; the codebase expresses leadership
--     inline in every policy. Define it ONCE here (same role list as the
--     existing pastoral_followups_read policy) so the rule lives in one place.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.is_tenant_leadership()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid()
       AND p.role IN ('superadmin','super_admin','coa_employee','employee',
                      'admin','pastor','bishop','apostle','prophet',
                      'general_secretary','general_treasurer','treasurer',
                      'secretary','assistant_pastor','leader')
  );
$$;

REVOKE ALL ON FUNCTION public.is_tenant_leadership() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_tenant_leadership() TO authenticated, service_role;


-- ═══ 0b. Safety net: the historic D1 bug (dashboard filtered 'pending',
--         but the column only ever holds open|done|cancelled). Normalise any
--         stray rows BEFORE adding the constraint so nothing is lost.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='pastoral_followups') THEN
    UPDATE public.pastoral_followups
       SET status = 'open'
     WHERE status IS NULL
        OR status NOT IN ('open','done','cancelled');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'pastoral_followups_status_check'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='pastoral_followups'
  ) THEN
    ALTER TABLE public.pastoral_followups
      ADD CONSTRAINT pastoral_followups_status_check
      CHECK (status IN ('open','done','cancelled'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_pastoral_followups_open
  ON public.pastoral_followups (tenant_id, status, follow_up_at)
  WHERE status = 'open';


-- ═══════════════════════════════════════════════════════════════════════════
-- 1. VISITOR STATUS ON PROFILES  (drives items 1, 4, 8, 11)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS visitor_status TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_visit_at TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_service_date DATE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS services_attended INT NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS baptism_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname='profiles_visitor_status_check') THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_visitor_status_check
      CHECK (visitor_status IS NULL
          OR visitor_status IN ('visitor','returning','regular','member','inactive'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_visitor_status
  ON public.profiles (tenant_id, visitor_status)
  WHERE visitor_status IS NOT NULL;

-- households FK added after the households table is created (see §2)


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. HOUSEHOLDS — the unit of care and of giving
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.households (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  -- Address doubles as the household's location + the print label
  address        TEXT,
  phone_number   TEXT,
  envelope_code  TEXT,                       -- e.g. "ROA-0142" (giving statement)
  notes          TEXT,
  head_member_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_households_tenant ON public.households (tenant_id, name);
CREATE UNIQUE INDEX IF NOT EXISTS ux_households_envelope
  ON public.households (tenant_id, envelope_code)
  WHERE envelope_code IS NOT NULL AND envelope_code <> '';

ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "households_select_tenant" ON public.households
    FOR SELECT TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "households_insert_leadership" ON public.households
    FOR INSERT TO authenticated
    WITH CHECK (tenant_id::text = public.get_my_tenant_id()
                AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "households_update_leadership" ON public.households
    FOR UPDATE TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id()
           AND public.is_tenant_leadership())
    WITH CHECK (tenant_id::text = public.get_my_tenant_id()
                AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "households_delete_leadership" ON public.households
    FOR DELETE TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id()
           AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.touch_households_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_households_updated_at ON public.households;
CREATE TRIGGER trg_households_updated_at
  BEFORE UPDATE ON public.households
  FOR EACH ROW EXECUTE FUNCTION public.touch_households_updated_at();

-- profiles -> household (the people side of the family)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS household_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_household_id_fkey'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_household_id_fkey
      FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_household
  ON public.profiles (household_id) WHERE household_id IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════════════
-- 1 (cont). AUTO FOLLOW-UP ON FIRST VISITOR MARK  — the Breeze trigger
-- ═══════════════════════════════════════════════════════════════════════════
-- A SECURITY DEFINER function so a usher/member marking a visitor does not
-- need INSERT rights on pastoral_followups.
CREATE OR REPLACE FUNCTION public.set_visitor_status(
  p_user_id UUID,
  p_visitor_status TEXT DEFAULT 'visitor',
  p_actor UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile   public.profiles%ROWTYPE;
  v_tenant    UUID;
  v_tenant_txt TEXT;
  v_actor     UUID;
  v_is_new    BOOLEAN := FALSE;
  v_followup  UUID;
  v_msg       TEXT;
BEGIN
  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;

  v_actor := COALESCE(p_actor, auth.uid());

  -- Authorisation: self, or tenant leadership.
  IF v_actor IS DISTINCT FROM p_user_id THEN
    v_tenant_txt := v_profile.tenant_id;
    IF v_tenant_txt IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.profiles a
       WHERE a.id = v_actor
         AND a.tenant_id::text = v_tenant_txt
         AND a.role IN ('superadmin','super_admin','coa_employee','employee',
                        'admin','pastor','bishop','apostle','prophet',
                        'general_secretary','general_treasurer','treasurer')
    ) THEN
      RAISE EXCEPTION 'not_authorised';
    END IF;
  END IF;

  -- Only the 'visitor' transition auto-creates work (Breeze: first visit).
  v_is_new := (v_profile.visitor_status IS DISTINCT FROM 'visitor')
              AND p_visitor_status = 'visitor';

  -- Resolve the tenant as UUID (pastoral_followups.tenant_id is uuid)
  v_tenant := COALESCE(
    NULLIF(v_profile.tenant_id, '')::uuid,
    v_profile.tenant_id_uuid,
    (SELECT c.tenant_id FROM public.churches c WHERE c.id = v_profile.church_id)
  );

  UPDATE public.profiles
     SET visitor_status    = p_visitor_status,
         first_visit_at    = COALESCE(first_visit_at,
                                      CASE WHEN p_visitor_status = 'visitor'
                                           THEN now() ELSE NULL END),
         updated_at        = now()
   WHERE id = p_user_id;

  IF v_is_new AND v_tenant IS NOT NULL THEN
    INSERT INTO public.pastoral_followups
      (tenant_id, member_id, followup_type, notes, status,
       follow_up_at, created_by)
    VALUES
      (v_tenant, p_user_id, 'visit',
       'Auto-created: first marked as a visitor. Welcome them and invite to join a group.',
       'open', now(), v_actor)
    RETURNING id INTO v_followup;

    v_msg := 'first_visit_followup_created';
  ELSE
    v_followup := NULL;
    v_msg := CASE WHEN v_is_new THEN 'followup_not_created_no_tenant'
                  ELSE 'status_updated' END;
  END IF;

  -- Optional notification to leadership (never fails the write). The
  -- notifications table shape has drifted across deployments, so this is
  -- best-effort by design.
  IF v_is_new AND v_tenant IS NOT NULL THEN
    BEGIN
      INSERT INTO public.notifications
        (user_id, type, title, body, data, created_at)
      SELECT a.id,
             'pastoral_followup',
             'New visitor',
             COALESCE(v_profile.full_name, 'A member')
               || ' was marked as a visitor — welcome them today.',
             jsonb_build_object('user_id', p_user_id, 'followup_id', v_followup),
             now()
        FROM public.profiles a
       WHERE a.tenant_id::text = v_profile.tenant_id
         AND a.id <> p_user_id
         AND a.role IN ('superadmin','coa_employee','admin','pastor','bishop',
                        'apostle','prophet','general_secretary','treasurer');
    EXCEPTION
      WHEN others THEN NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'status',            p_visitor_status,
    'first_visit',       v_is_new,
    'followup_id',       v_followup,
    'result',            v_msg,
    'visitor_status',    p_visitor_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_visitor_status(UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_visitor_status(UUID, TEXT, UUID)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. "PEOPLE TO SEE TODAY" — one RPC, four care signals
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_people_to_see_today(
  p_tenant_id UUID,
  p_absent_days INT DEFAULT 28,
  p_unbaptised_days INT DEFAULT 90
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSONB;
  v_due INT := 0;
  v_newish INT := 0;
  v_absent INT := 0;
  v_unbap INT := 0;
BEGIN
  IF NOT public.is_tenant_leadership() AND NOT public.is_platform_staff() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  WITH att AS (
    -- Prefer member_attendance (the pastoral table); fall back to
    -- attendance_logs (the event-scan table) when a church only has that.
    SELECT user_id, max(service_date) AS last_date, count(DISTINCT service_date) AS n
      FROM public.member_attendance
     WHERE tenant_id = p_tenant_id::text
     GROUP BY user_id
  ), att2 AS (
    SELECT user_id, max(check_in_time::date) AS last_date, count(DISTINCT check_in_time::date) AS n
      FROM public.attendance_logs
     WHERE tenant_id = p_tenant_id
     GROUP BY user_id
  ), merged AS (
    SELECT user_id,
           max(last_date) AS last_date,   -- latest across both sources
           sum(n)         AS n            -- total distinct services
      FROM (
        SELECT * FROM att
        UNION ALL
        SELECT * FROM att2
      ) z
     GROUP BY user_id
  )
  SELECT coalesce(jsonb_agg(row_to_json(t) ORDER BY t.priority, t.name), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT
      p.id,
      COALESCE(p.full_name, 'Unnamed') AS name,
      p.avatar_url,
      p.visitor_status,
      p.role,
      p.household_id,
      COALESCE(m.last_date, p.last_service_date) AS last_seen,
      COALESCE(m.n, p.services_attended, 0)     AS services,
      (b.id IS NOT NULL)                        AS baptized,
      f.id                                      AS followup_id,
      f.followup_type,
      f.follow_up_at,
      f.notes                                   AS followup_notes,
      -- priority: 0 = due follow-up, 1 = 2nd-week visitor, 2 = absent,
      --           3 = long-unbaptised
      CASE
        WHEN f.id IS NOT NULL AND (f.follow_up_at IS NULL OR f.follow_up_at <= now()) THEN 0
        WHEN f.id IS NOT NULL THEN 1
        WHEN p.visitor_status = 'visitor'
             AND p.first_visit_at IS NOT NULL
             AND p.first_visit_at::date BETWEEN (current_date - 14) AND (current_date - 3)
          THEN 2
        WHEN COALESCE(m.n, 0) >= 1
             AND COALESCE(m.last_date, p.last_service_date) < (current_date - p_absent_days)
          THEN 3
        WHEN b.id IS NULL
             AND p.first_visit_at IS NOT NULL
             AND p.first_visit_at::date < (current_date - p_unbaptised_days)
          THEN 4
        ELSE 9
      END AS priority,
      -- why this person surfaced (drives the row subtitle in the UI)
      concat_ws(', ',
        CASE WHEN f.id IS NOT NULL AND (f.follow_up_at IS NULL OR f.follow_up_at <= now())
             THEN 'Follow-up due' END,
        CASE WHEN f.id IS NOT NULL AND f.follow_up_at > now()
             THEN 'Follow-up scheduled' END,
        CASE WHEN p.visitor_status = 'visitor'
                  AND p.first_visit_at::date BETWEEN (current_date - 14) AND (current_date - 3)
             THEN 'New visitor — 2nd week' END,
        CASE WHEN COALESCE(m.n,0) >= 1
                  AND COALESCE(m.last_date, p.last_service_date) < (current_date - p_absent_days)
             THEN 'Absent ' || (
                 current_date - COALESCE(m.last_date, p.last_service_date)
               ) || ' days' END,
        CASE WHEN b.id IS NULL AND p.first_visit_at::date < (current_date - p_unbaptised_days)
             THEN 'Un-baptised ' || (
                 current_date - p.first_visit_at::date
               ) || ' days' END
      ) AS reason
    FROM public.profiles p
    LEFT JOIN merged m ON m.user_id = p.id
    LEFT JOIN public.baptisms b
           ON b.user_id = p.id
          AND lower(b.status) IN ('verified','approved','complete','completed')
    LEFT JOIN LATERAL (
      SELECT pf.id, pf.followup_type, pf.follow_up_at, pf.notes
        FROM public.pastoral_followups pf
       WHERE pf.member_id = p.id
         AND pf.tenant_id = p_tenant_id
         AND pf.status = 'open'
       ORDER BY (pf.follow_up_at IS NULL) DESC, pf.follow_up_at ASC NULLS FIRST
       LIMIT 1
    ) f ON TRUE
   WHERE p.tenant_id::text = p_tenant_id::text
     AND p.deleted_at IS NULL
     AND p.id <> auth.uid()
     -- a live service is "seen" — don't nag people who came today
     AND COALESCE(m.last_date, p.last_service_date) IS DISTINCT FROM current_date
  ) t
  WHERE t.priority < 9;

  -- Per-signal counts for the card header
  SELECT count(*) INTO v_due FROM jsonb_array_elements(coalesce(v_rows,'[]'::jsonb))
   WHERE (j->>'priority')::int = 0;
  SELECT count(*) INTO v_newish FROM jsonb_array_elements(coalesce(v_rows,'[]'::jsonb))
   WHERE (j->>'priority')::int = 2;
  SELECT count(*) INTO v_absent FROM jsonb_array_elements(coalesce(v_rows,'[]'::jsonb))
   WHERE (j->>'priority')::int = 3;
  SELECT count(*) INTO v_unbap FROM jsonb_array_elements(coalesce(v_rows,'[]'::jsonb))
   WHERE (j->>'priority')::int = 4;

  RETURN jsonb_build_object(
    'people', v_rows,
    'due_followups',  v_due,
    'new_visitors',   v_newish,
    'absent',         v_absent,
    'unbaptised',     v_unbap,
    'total',          jsonb_array_length(coalesce(v_rows,'[]'::jsonb))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_people_to_see_today(UUID, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_people_to_see_today(UUID, INT, INT)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 8. VISITOR RETENTION — first-time vs returning vs regular, month over month
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_visitor_retention(
  p_tenant_id UUID,
  p_months INT DEFAULT 6
) RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH months AS (
    SELECT to_char(date_trunc('month', d), 'YYYY-MM') AS ym
      FROM generate_series(
             date_trunc('month', now()) - make_interval(months => p_months - 1),
             date_trunc('month', now()),
             interval '1 month') d
  ), per_month AS (
    SELECT m.ym,
           -- first-time = their FIRST EVER recorded service falls in this month
           count(DISTINCT ma.user_id) FILTER (
             WHERE (SELECT min(ma2.service_date) FROM public.member_attendance ma2
                     WHERE ma2.user_id = ma.user_id
                       AND ma2.tenant_id = p_tenant_id::text)
                   BETWEEN (m.ym || '-01')::date
                       AND (date_trunc('month', (m.ym || '-01')::date)
                            + interval '1 month - 1 day')::date
           ) AS first_time,
           count(DISTINCT ma.user_id) AS attended
      FROM months m
      LEFT JOIN public.member_attendance ma
        ON ma.tenant_id = p_tenant_id::text
       AND to_char(ma.service_date, 'YYYY-MM') = m.ym
     GROUP BY m.ym
  ), buckets AS (
    SELECT p.id,
           COALESCE(p.visitor_status, 'unclassified') AS bucket,
           (SELECT max(service_date) FROM public.member_attendance ma
             WHERE ma.user_id = p.id
               AND ma.tenant_id = p_tenant_id::text) AS last_seen
      FROM public.profiles p
     WHERE p.tenant_id::text = p_tenant_id::text
       AND p.deleted_at IS NULL
  )
  SELECT jsonb_build_object(
    'months', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'month', ym, 'first_time', first_time, 'attended', attended)
        ORDER BY ym), '[]'::jsonb) FROM per_month),
    'totals', jsonb_build_object(
      'first_time',  (SELECT count(*) FROM buckets WHERE bucket = 'visitor'),
      'returning',   (SELECT count(*) FROM buckets WHERE bucket = 'returning'),
      'regular',     (SELECT count(*) FROM buckets WHERE bucket = 'regular'),
      'member',      (SELECT count(*) FROM buckets WHERE bucket = 'member'),
      'inactive',    (SELECT count(*) FROM buckets
                        WHERE bucket <> 'inactive'
                          AND last_seen < current_date - 60)
    )
  );
$$;

REVOKE ALL ON FUNCTION public.get_visitor_retention(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_visitor_retention(UUID, INT)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 11. AUTO-TAG REGULAR ATTENDERS  (>= N services in M months)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.refresh_attendance_tags(
  p_tenant_id UUID,
  p_regular_threshold INT DEFAULT 6,
  p_window_months INT DEFAULT 4
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_regular INT := 0;
  v_promoted INT := 0;
  v_demoted INT := 0;
BEGIN
  IF NOT public.is_tenant_leadership() AND NOT public.is_platform_staff() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  WITH att AS (
    SELECT user_id,
           count(DISTINCT service_date) AS n,
           max(service_date)          AS last_date
      FROM public.member_attendance
     WHERE tenant_id = p_tenant_id::text
       AND service_date >= (current_date - make_interval(months => p_window_months))
     GROUP BY user_id
  ), upd AS (
    UPDATE public.profiles p
       SET services_attended  = COALESCE(a.n, 0),
           last_service_date  = a.last_date,
           visitor_status = CASE
             WHEN a.n >= p_regular_threshold THEN 'regular'
             WHEN a.n >= 2 THEN 'returning'
             ELSE COALESCE(p.visitor_status, 'visitor')
           END,
           updated_at = now()
      FROM att a
     WHERE p.id = a.user_id
       AND p.tenant_id::text = p_tenant_id::text
     RETURNING p.id, p.visitor_status
  )
  SELECT count(*) FILTER (WHERE visitor_status = 'regular'),
         count(*) FILTER (WHERE visitor_status = 'returning')
    INTO v_regular, v_promoted
    FROM upd;

  -- Demote long-absent regulars to 'inactive' (never touch members)
  WITH stale AS (
    UPDATE public.profiles p
       SET visitor_status = 'inactive'
     WHERE p.tenant_id::text = p_tenant_id::text
       AND p.visitor_status IN ('regular','returning')
       AND COALESCE(p.last_service_date, DATE '1900-01-01') < (current_date - 60)
     RETURNING 1
  ) SELECT count(*) INTO v_demoted FROM stale;

  RETURN jsonb_build_object(
    'regular',   v_regular,
    'returning', v_promoted,
    'inactive',  v_demoted,
    'threshold', p_regular_threshold,
    'window_months', p_window_months
  );
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_attendance_tags(UUID, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_attendance_tags(UUID, INT, INT)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 6. ATTENDANCE AUTOMATIONS (nudges)
-- ═══════════════════════════════════════════════════════════════════════════
-- Fires on a check-in: 3+ services in 4 weeks -> invite to a group;
-- baptism candidate past 90 days -> confirm the date.
CREATE OR REPLACE FUNCTION public.attendance_automation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_name   TEXT;
  v_n      INT;
BEGIN
  SELECT COALESCE(NULLIF(p.tenant_id,'')::uuid, p.tenant_id_uuid)
    INTO v_tenant
    FROM public.profiles p WHERE p.id = NEW.user_id;

  SELECT full_name INTO v_name FROM public.profiles WHERE id = NEW.user_id;
  IF v_tenant IS NULL OR v_name IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(DISTINCT service_date) INTO v_n
    FROM public.member_attendance
   WHERE user_id = NEW.user_id
     AND service_date >= (current_date - 28);

  -- Automation 1: 3 visits in 4 weeks -> invite them to a group.
  IF v_n >= 3 THEN
    INSERT INTO public.pastoral_followups
      (tenant_id, member_id, followup_type, notes, status, follow_up_at, created_by)
    SELECT v_tenant, NEW.user_id, 'whatsapp',
           'Auto: attended ' || v_n || ' services in 4 weeks — invite them to join a group.',
           'open', now(), NEW.checked_in_by
     WHERE NOT EXISTS (
       SELECT 1 FROM public.pastoral_followups f
        WHERE f.member_id = NEW.user_id
          AND f.tenant_id = v_tenant
          AND f.status = 'open'
          AND f.notes LIKE 'Auto: attended%'
     );
  END IF;

  -- Automation 2: baptism candidate 90+ days -> confirm the date.
  -- NOTE: baptisms.status is 'Pending' | 'Verified' (capitalised by the app).
  IF EXISTS (
    SELECT 1 FROM public.baptisms b
     WHERE b.user_id = NEW.user_id
       AND b.tenant_id::text = v_tenant::text
       AND lower(b.status) = 'pending'
       AND b.date < now() - interval '90 days'
  ) THEN
    INSERT INTO public.pastoral_followups
      (tenant_id, member_id, followup_type, notes, status, follow_up_at, created_by)
    SELECT v_tenant, NEW.user_id, 'phone',
           'Auto: baptism date has passed — confirm the new date with the candidate.',
           'open', now(), NEW.checked_in_by
     WHERE NOT EXISTS (
       SELECT 1 FROM public.pastoral_followups f
        WHERE f.member_id = NEW.user_id
          AND f.tenant_id = v_tenant
          AND f.status = 'open'
          AND f.notes LIKE 'Auto: baptism date%'
     );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attendance_automation ON public.member_attendance;
CREATE TRIGGER trg_attendance_automation
  AFTER INSERT ON public.member_attendance
  FOR EACH ROW EXECUTE FUNCTION public.attendance_automation();


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. ORDER OF SERVICE — service_plans (order-of-service lite)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.service_plans (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  service_date  DATE NOT NULL,
  title         TEXT NOT NULL,
  setlist_id    UUID REFERENCES public.worship_setlists(id) ON DELETE SET NULL,
  speakers      TEXT[] NOT NULL DEFAULT '{}'::text[],
  ushers        UUID[] NOT NULL DEFAULT '{}'::uuid[],
  musicians     UUID[] NOT NULL DEFAULT '{}'::uuid[],
  notes         TEXT,
  is_published  BOOLEAN NOT NULL DEFAULT FALSE,
  published_at  TIMESTAMPTZ,
  created_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_plans_tenant_date
  ON public.service_plans (tenant_id, service_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_service_plans_tenant_date
  ON public.service_plans (tenant_id, service_date);

ALTER TABLE public.service_plans ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "service_plans_select_tenant" ON public.service_plans
    FOR SELECT TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "service_plans_write_leadership" ON public.service_plans
    FOR ALL TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership())
    WITH CHECK (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.touch_service_plans_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_service_plans_updated_at ON public.service_plans;
CREATE TRIGGER trg_service_plans_updated_at
  BEFORE UPDATE ON public.service_plans
  FOR EACH ROW EXECUTE FUNCTION public.touch_service_plans_updated_at();

-- Publish toggle (sets published_at server-side; client never writes it)
CREATE OR REPLACE FUNCTION public.publish_service_plan(p_plan_id UUID, p_publish BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  SELECT tenant_id INTO v_tenant FROM public.service_plans WHERE id = p_plan_id;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF NOT (public.is_tenant_leadership() OR public.is_platform_staff()) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  UPDATE public.service_plans
     SET is_published = p_publish,
         published_at = CASE WHEN p_publish THEN now() ELSE NULL END
   WHERE id = p_plan_id;

  RETURN jsonb_build_object('id', p_plan_id, 'is_published', p_publish);
END;
$$;

REVOKE ALL ON FUNCTION public.publish_service_plan(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_service_plan(UUID, BOOLEAN)
  TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 9. VOLUNTEER ROTA LITE — who serves when (+ WhatsApp nudge)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.volunteer_roster (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  -- A slot may be a known member OR a manual entry (someone serving who has
  -- no app account yet). Exactly one of the two is set.
  user_id       UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  volunteer_name TEXT,
  role_label    TEXT NOT NULL,
  service_date  DATE NOT NULL,
  notes         TEXT,
  notified_at   TIMESTAMPTZ,
  created_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT volunteer_roster_who_check
    CHECK (user_id IS NOT NULL OR NULLIF(TRIM(volunteer_name), '') IS NOT NULL)
);

-- `CREATE TABLE IF NOT EXISTS` silently skips a table that already exists, so
-- make the nullable-user shape explicit for a re-run of this migration.
ALTER TABLE public.volunteer_roster
  ADD COLUMN IF NOT EXISTS volunteer_name TEXT;
-- Manual slots have no profile to read a number from, so the WhatsApp number
-- is captured when the slot is created.
ALTER TABLE public.volunteer_roster
  ADD COLUMN IF NOT EXISTS phone_number TEXT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'volunteer_roster_user_id_not_null'
  ) THEN
    ALTER TABLE public.volunteer_roster
      DROP CONSTRAINT volunteer_roster_user_id_not_null;
  END IF;
END $$;

ALTER TABLE public.volunteer_roster ALTER COLUMN user_id DROP NOT NULL;

-- Backfill the manual-entry name for any slot added before this column.
UPDATE public.volunteer_roster
   SET volunteer_name = COALESCE(volunteer_name, p.full_name, 'Volunteer')
  FROM public.profiles p
 WHERE p.id = public.volunteer_roster.user_id;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'volunteer_roster_who_check') THEN
    ALTER TABLE public.volunteer_roster
      ADD CONSTRAINT volunteer_roster_who_check
      CHECK (user_id IS NOT NULL
             OR NULLIF(TRIM(volunteer_name), '') IS NOT NULL);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_volunteer_roster_tenant_date
  ON public.volunteer_roster (tenant_id, service_date);
CREATE INDEX IF NOT EXISTS idx_volunteer_roster_user
  ON public.volunteer_roster (user_id, service_date DESC)
  WHERE user_id IS NOT NULL;

ALTER TABLE public.volunteer_roster ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "volunteer_roster_select_tenant" ON public.volunteer_roster
    FOR SELECT TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id()
           OR (user_id IS NOT NULL AND user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "volunteer_roster_write_leadership" ON public.volunteer_roster
    FOR ALL TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership())
    WITH CHECK (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 12. DELEGATE PERMISSIONS — scoped roles for ushers/deacons
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.role_delegations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- 'attendance' | 'followups' | 'events' | 'giving' | 'media' | 'members'
  scope         TEXT NOT NULL,
  granted_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, scope)
);

CREATE INDEX IF NOT EXISTS idx_role_delegations_user
  ON public.role_delegations (user_id);

ALTER TABLE public.role_delegations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "role_delegations_select_own" ON public.role_delegations
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR tenant_id::text = public.get_my_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "role_delegations_write_leadership" ON public.role_delegations
    FOR ALL TO authenticated
    USING (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership())
    WITH CHECK (tenant_id::text = public.get_my_tenant_id() AND public.is_tenant_leadership());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- What can this caller do in this tenant? Used by the client to gate actions
-- and by RLS helpers to widen ushers/deacons without touching profiles.role.
CREATE OR REPLACE FUNCTION public.has_delegated_scope(p_scope TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.role_delegations d
     WHERE d.user_id = auth.uid()
       AND d.scope = p_scope
       AND d.tenant_id::text IS NOT DISTINCT FROM public.get_my_tenant_id()
  )
  OR public.is_tenant_leadership()
  OR public.is_platform_staff();
$$;

REVOKE ALL ON FUNCTION public.has_delegated_scope(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_delegated_scope(TEXT) TO authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2 (cont). HOUSEHOLD GIVING STATEMENT
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_household_giving_statement(
  p_household_id UUID,
  p_from DATE,
  p_to DATE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_h  public.households%ROWTYPE;
  v_sum NUMERIC := 0;
  v_cnt INT := 0;
BEGIN
  SELECT * INTO v_h FROM public.households WHERE id = p_household_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF NOT (public.is_tenant_leadership() OR public.is_platform_staff()
          OR public.get_my_tenant_id()::text = v_h.tenant_id::text) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT COALESCE(sum(t.amount), 0), count(*)
    INTO v_sum, v_cnt
    FROM public.transactions t
    JOIN public.profiles p ON p.id = t.user_id
   WHERE p.household_id = p_household_id
     AND t.status = 'completed'
     AND t.created_at::date BETWEEN p_from AND p_to;

  RETURN jsonb_build_object(
    'household_id',   v_h.id,
    'name',           v_h.name,
    'envelope_code',  v_h.envelope_code,
    'from',           p_from,
    'to',             p_to,
    'total',          v_sum,
    'transactions',   v_cnt,
    'members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'full_name', p.full_name,
               'role', p.role, 'phone_number', p.phone_number)),
             '[]'::jsonb)
        FROM public.profiles p WHERE p.household_id = p_household_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_household_giving_statement(UUID, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_household_giving_statement(UUID, DATE, DATE)
  TO authenticated, service_role;

-- realtime for the new tables the client subscribes to
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.households;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.service_plans;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.volunteer_roster;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pastoral_followups;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
