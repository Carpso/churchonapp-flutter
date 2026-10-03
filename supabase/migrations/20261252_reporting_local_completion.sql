-- ============================================================================
-- Reporting chain: a return can be FINALISED LOCALLY, conference is optional
-- ============================================================================
-- WHY
-- 20261250 modelled the chain as mandatory:
--
--     draft -> submitted -> returned -> approved -> submitted_hq -> acknowledged
--
-- which asserts that the conference step always happens. That is wrong twice
-- over:
--
--   1. MANY CHURCHES HAVE NO CONFERENCE. `churches.organization_id` is NULL for
--      a standalone church, so there is nothing to send a return to. The
--      `submitted_hq` step can never be reached, the return sits at `approved`
--      forever, and nothing anywhere tells the pastor "you are finished" - so
--      the honest outcome (approved, done) is indistinguishable from a stalled
--      workflow.
--   2. EVEN WHERE THERE IS A CONFERENCE, sending to HQ is a CHOICE the church
--      makes. Forcing it removes the ability to say "this month is closed and
--      final" without also claiming to have escalated it.
--
-- So a new status is added:
--
--     local_complete = "the pastor reviewed it, it is approved, and it is FINAL
--                      HERE. It has deliberately NOT been sent to conference."
--
--     draft -> submitted -> returned -> approved -> local_complete   (done)
--                                                          \-> submitted_hq  (optional)
--
-- `local_complete` is not a quieter `approved`:
--   * `reopen_local_report` puts it back to `approved`, so a mistake is
--     correctable without re-running the review.
--   * `save_report_draft` refuses to edit a finalised return, so "final" means
--     the numbers cannot quietly change afterwards.
--   * `send_reports_to_hq` still only ever carries APPROVED or FINALISED
--     numbers upward. Nothing unapproved can reach the conference.
--
-- ALSO FIXED HERE - the secretary could not file at all.
-- `save_report_draft` gated on `is_tenant_leadership(p_tenant_id)`, whose role
-- list has no conference secretary: it only knows roles stored on
-- `profiles.role`. But a conference secretary is recorded on the ORGANIZATION
-- (`organizations.secretary_id`), which is the only place their office exists.
-- The intended user - the secretary who consolidates branch returns for the
-- conference - was therefore blocked by the very workflow built for them,
-- while `report_submissions` RLS already let them read the returns. The gate is
-- now widened to the org secretary of the organization that owns the church.
-- They are deliberately NOT required to be a member of the branch they report
-- for: one secretary covers many branches, so a tenant-membership test would
-- re-block the legitimate case.
--
-- PARAMETER NAMES in the replaced `save_report_draft` are unchanged on purpose:
-- CREATE OR REPLACE cannot rename an input parameter (error 42P13), and the
-- Dart client keeps sending the same `p_*` names.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Widen the status CHECK.
--
-- Dropped by matching any CHECK constraint whose definition mentions `status`
-- rather than by a hardcoded name, so this stays correct if the original
-- constraint was renamed by an earlier migration. `report_period_order` does
-- not mention `status` and is therefore left alone.
--
-- `local_complete` sits between `approved` and `submitted_hq` because that is
-- the real order: you finalise locally first, and may escalate afterwards.
-- Every pre-existing value is preserved - no row can become invalid.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'public.report_submissions'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.report_submissions DROP CONSTRAINT %I', r.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.report_submissions
  ADD CONSTRAINT report_submissions_status_check
  CHECK (status IN ('draft','submitted','returned','approved',
                    'local_complete','submitted_hq','acknowledged'));

-- ---------------------------------------------------------------------------
-- 2. Who may put the final signature on a return.
--
-- Extracted as one function so `complete_report_locally` and
-- `reopen_local_report` cannot drift apart from each other or from the guard
-- `review_report` already applies. A return is never signed off by the person
-- who prepared it; finalising is a second signature on the same document, so
-- it needs the same separation.
--
-- SECURITY DEFINER: it reads `profiles` and `organizations`, both of which are
-- RLS-protected, and the question has to be answered against the real rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_report_finaliser(
  p_row public.report_submissions
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role IN ('superadmin','super_admin','coa_employee','employee') THEN
    RETURN;  -- platform oversight
  END IF;

  -- Leadership of the reporting church may finalise its own return. Failing
  -- that, leadership of its conference (bishop / secretary / treasurer) may
  -- finalise on the branch's behalf - the same fallback `review_report` uses.
  IF NOT public.is_tenant_leadership(p_row.tenant_id) THEN
    IF p_row.organization_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.organizations o
          WHERE o.id = p_row.organization_id
            AND (o.bishop_id = v_uid OR o.secretary_id = v_uid
                 OR o.treasurer_id = v_uid)
       )
       AND v_role NOT IN ('bishop','apostle','prophet') THEN
      RAISE EXCEPTION 'only the pastor or conference leadership may finalise this return';
    END IF;
  END IF;

  IF p_row.prepared_by = v_uid THEN
    RAISE EXCEPTION 'a return cannot be finalised by the person who prepared it';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_report_finaliser(public.report_submissions)
  FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 3. The pastor closes the period locally. approved -> local_complete.
--
-- The transition is one-way and only from `approved`, so a return cannot be
-- declared final before somebody has actually reviewed it: the only way into
-- `approved` is `review_report`, which is where the approval note lives.
-- `reviewed_by`/`reviewed_at`/`review_note` are left untouched - the approval
-- record is the audit trail and must survive finalisation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_report_locally(
  p_submission_id UUID
)
RETURNS public.report_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.report_submissions;
BEGIN
  SELECT * INTO v_row
    FROM public.report_submissions
   WHERE id = p_submission_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'return not found'; END IF;

  IF v_row.status <> 'approved' THEN
    RAISE EXCEPTION 'only an approved return can be finalised locally (this one is %)',
      v_row.status;
  END IF;

  PERFORM public.assert_report_finaliser(v_row);

  UPDATE public.report_submissions
     SET status = 'local_complete',
         updated_at = now()
   WHERE id = p_submission_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_report_locally(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_report_locally(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Correct a mistake: local_complete -> approved.
--
-- Same guards as finalising, because reopening hands the return back to the
-- approval step and the person who may do that must be the person who was
-- allowed to close it. The audit trail (reviewed_by / review_note) is kept, so
-- a reopen is visible rather than silent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reopen_local_report(
  p_submission_id UUID
)
RETURNS public.report_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.report_submissions;
BEGIN
  SELECT * INTO v_row
    FROM public.report_submissions
   WHERE id = p_submission_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'return not found'; END IF;

  IF v_row.status <> 'local_complete' THEN
    RAISE EXCEPTION 'only a return finalised locally can be reopened (this one is %)',
      v_row.status;
  END IF;

  PERFORM public.assert_report_finaliser(v_row);

  UPDATE public.report_submissions
     SET status = 'approved',
         updated_at = now()
   WHERE id = p_submission_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.reopen_local_report(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reopen_local_report(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Let the conference secretary file.
--
-- Replaces `save_report_draft` from 20261250. Parameter names, defaults and
-- return type are byte-for-byte the same (CREATE OR REPLACE cannot rename an
-- input parameter), so no client change is required.
--
-- Three changes to the body:
--   a. The organization's id is resolved BEFORE the authorisation check,
--      because the new rule needs it.
--   b. `organizations.secretary_id` of the organization that owns this church
--      may file, alongside the church's own leadership.
--   c. A `local_complete` return is locked: it is final, so figures must be
--      reopened (`reopen_local_report`) rather than edited in place.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_report_draft(
  p_tenant_id TEXT,
  p_report_type TEXT,
  p_period_start DATE,
  p_period_end DATE,
  p_period_label TEXT,
  p_data JSONB DEFAULT '{}'::jsonb,
  p_tithe_total NUMERIC DEFAULT 0,
  p_offering_total NUMERIC DEFAULT 0,
  p_other_income_total NUMERIC DEFAULT 0,
  p_attendance_total INT DEFAULT 0,
  p_new_members INT DEFAULT 0,
  p_baptisms INT DEFAULT 0,
  p_salvations INT DEFAULT 0,
  p_narrative TEXT DEFAULT NULL,
  p_submit BOOLEAN DEFAULT false
)
RETURNS public.report_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_org UUID;
  v_is_org_secretary BOOLEAN := false;
  v_existing_status TEXT;
  v_row public.report_submissions;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_report_type NOT IN ('monthly','quarterly') THEN
    RAISE EXCEPTION 'unknown report type %', p_report_type;
  END IF;
  IF p_period_end < p_period_start THEN
    RAISE EXCEPTION 'the period end date is before the start date';
  END IF;

  -- Resolved first: the conference-secretary rule below is scoped to the
  -- organization that OWNS this church.
  -- NOTE the `::text` casts: `profiles.tenant_id` is TEXT while
  -- `tenants.id` / `churches.id` are UUID. Without the cast Postgres raises
  -- `operator does not exist: text = uuid` and the whole call fails.
  SELECT c.organization_id INTO v_org
    FROM public.churches c
   WHERE c.tenant_id::text = p_tenant_id
      OR c.id::text = p_tenant_id
   LIMIT 1;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    -- A conference secretary's office lives on the ORGANIZATION, not on
    -- `profiles.role`, so `is_tenant_leadership` cannot see them. Their being
    -- named here is the whole point of `organizations.secretary_id`.
    v_is_org_secretary := v_org IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = v_org AND o.secretary_id = v_uid
    );

    -- A secretary or any leader of THAT church may prepare its return.
    IF NOT public.is_tenant_leadership(p_tenant_id)
       AND NOT v_is_org_secretary THEN
      RAISE EXCEPTION
        'only leadership of this church, or its conference secretary, may file its return';
    END IF;

    -- Branch staff must belong to the church they are reporting for. The
    -- conference secretary is exempt: one secretary consolidates several
    -- branches and is normally not a member of any of them.
    IF NOT v_is_org_secretary AND NOT EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = v_uid AND tenant_id::text = p_tenant_id
    ) THEN
      RAISE EXCEPTION 'only someone in this church may file its return';
    END IF;
  END IF;

  -- "Finalised locally" has to mean final. Locking the row here (rather than
  -- trusting the status in the upsert below) also stops two secretaries
  -- editing the same period at once.
  SELECT rs.status INTO v_existing_status
    FROM public.report_submissions rs
   WHERE rs.tenant_id = p_tenant_id
     AND rs.report_type = p_report_type
     AND rs.period_start = p_period_start
   FOR UPDATE;
  IF v_existing_status = 'local_complete' THEN
    RAISE EXCEPTION
      'this return has been finalised locally - reopen it before making changes';
  END IF;

  INSERT INTO public.report_submissions
    (organization_id, tenant_id, template_id, report_type, period_start,
     period_end, period_label, status, data, tithe_total, offering_total,
     other_income_total, attendance_total, new_members, baptisms, salvations,
     narrative, prepared_by, prepared_at,
     submitted_by, submitted_at)
  VALUES
    (v_org, p_tenant_id, public.resolve_report_template(v_org, p_report_type),
     p_report_type, p_period_start, p_period_end, COALESCE(p_period_label, ''),
     CASE WHEN p_submit THEN 'submitted' ELSE 'draft' END,
     COALESCE(p_data, '{}'::jsonb), COALESCE(p_tithe_total, 0),
     COALESCE(p_offering_total, 0), COALESCE(p_other_income_total, 0),
     COALESCE(p_attendance_total, 0), COALESCE(p_new_members, 0),
     COALESCE(p_baptisms, 0), COALESCE(p_salvations, 0),
     p_narrative, v_uid, now(),
     CASE WHEN p_submit THEN v_uid END, CASE WHEN p_submit THEN now() END)
  ON CONFLICT (tenant_id, report_type, period_start) DO UPDATE SET
    data = EXCLUDED.data,
    tithe_total = EXCLUDED.tithe_total,
    offering_total = EXCLUDED.offering_total,
    other_income_total = EXCLUDED.other_income_total,
    attendance_total = EXCLUDED.attendance_total,
    new_members = EXCLUDED.new_members,
    baptisms = EXCLUDED.baptisms,
    salvations = EXCLUDED.salvations,
    narrative = EXCLUDED.narrative,
    prepared_by = v_uid,
    prepared_at = now(),
    updated_at = now(),
    -- Re-submitting a returned return puts it back in front of the pastor.
    status = CASE
      WHEN report_submissions.status = 'acknowledged'
        THEN report_submissions.status           -- locked, HQ has seen it
      WHEN p_submit THEN 'submitted'
      ELSE report_submissions.status
    END,
    submitted_by = CASE WHEN p_submit THEN v_uid
                        ELSE report_submissions.submitted_by END,
    submitted_at = CASE WHEN p_submit THEN now()
                        ELSE report_submissions.submitted_at END
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.save_report_draft(text, text, date, date, text, jsonb,
  numeric, numeric, numeric, int, int, int, int, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_report_draft(text, text, date, date, text, jsonb,
  numeric, numeric, numeric, int, int, int, int, text, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Escalation stays OPTIONAL - and stays possible.
--
-- `send_reports_to_hq` now also accepts `local_complete`, for one reason: a
-- return finalised locally means "approved, and deliberately not sent". If the
-- church later decides to escalate it, requiring a reopen first would force
-- the workflow to pretend the finalisation never happened.
--
-- The safety rule from 20261250 is unchanged and is the reason the new value is
-- listed here and nowhere else: an unapproved return still cannot reach the
-- conference, and only the bishop or the conference secretary can trigger it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_reports_to_hq(
  p_organization_id UUID,
  p_period_start DATE,
  p_period_end DATE,
  p_note TEXT DEFAULT NULL
)
RETURNS TABLE(sent_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_n INT := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = p_organization_id
         AND (o.bishop_id = v_uid OR o.secretary_id = v_uid)
    ) AND v_role NOT IN ('bishop','apostle','prophet') THEN
      RAISE EXCEPTION 'only the bishop or conference secretary may submit to HQ';
    END IF;
  END IF;

  -- Only APPROVED or FINALISED-LOCALLY returns go up. An unapproved return
  -- must not reach HQ.
  UPDATE public.report_submissions
     SET status = 'submitted_hq',
         sent_hq_by = v_uid,
         sent_hq_at = now(),
         narrative = COALESCE(p_note, narrative),
         updated_at = now()
   WHERE organization_id = p_organization_id
     AND period_start = p_period_start
     AND period_end = p_period_end
     AND status IN ('approved','local_complete');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN QUERY SELECT v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.send_reports_to_hq(uuid, date, date, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_reports_to_hq(uuid, date, date, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. Refuse to ship a chain that cannot finish locally.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  n INT;
  d TEXT;
  v_status TEXT;
BEGIN
  IF to_regclass('public.report_submissions') IS NULL THEN
    RAISE EXCEPTION 'report_submissions is missing - apply 20261250 first';
  END IF;

  -- The new status must actually be storable, or every finalise attempt fails
  -- with a CHECK violation and the church is back to a permanent "approved".
  d := (
    SELECT pg_get_constraintdef(oid)
      FROM pg_constraint
     WHERE conrelid = 'public.report_submissions'::regclass
       AND conname = 'report_submissions_status_check'
  );
  IF d IS NULL OR d NOT ILIKE '%local_complete%' THEN
    RAISE EXCEPTION 'report_submissions status CHECK does not allow local_complete';
  END IF;

  -- Widening the CHECK must not have quietly dropped a status: every value
  -- 20261250 allowed, plus local_complete, has to remain valid or existing
  -- rows stop being readable to their owner.
  FOREACH v_status IN ARRAY ARRAY['draft','submitted','returned','approved',
                                   'local_complete','submitted_hq','acknowledged']
  LOOP
    IF d NOT ILIKE ('%' || v_status || '%') THEN
      RAISE EXCEPTION 'status % was dropped while widening the CHECK', v_status;
    END IF;
  END LOOP;

  SELECT count(*) INTO n
    FROM pg_proc
   WHERE proname IN ('complete_report_locally','reopen_local_report',
                     'assert_report_finaliser')
     AND pronamespace = 'public'::regnamespace;
  IF n <> 3 THEN
    RAISE EXCEPTION 'expected 3 local-completion functions, found %', n;
  END IF;

  -- The secretary fix is the whole point of this migration for conference
  -- users: if a later rewrite drops the secretary branch, filing breaks again.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
     WHERE proname = 'save_report_draft'
       AND pronamespace = 'public'::regnamespace
       AND prosrc ILIKE '%organizations%'
       AND prosrc ILIKE '%secretary_id%'
  ) THEN
    RAISE EXCEPTION
      'save_report_draft no longer admits the conference secretary';
  END IF;

  -- Unchanged from 20261250: the chain is still only traversable via its RPCs.
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'report_submissions'
       AND cmd IN ('INSERT','UPDATE','DELETE')
  ) THEN
    RAISE EXCEPTION 'report_submissions must be written only via its workflow RPCs';
  END IF;
END;
$$;