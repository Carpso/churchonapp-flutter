-- ============================================================================
-- Monthly / quarterly reporting chain: local church -> secretary -> pastor -> HQ
-- ============================================================================
-- WHY
-- The app had no reporting chain at all. There was:
--   * `service_reports`     - a single Sunday service note (attendance,
--                             offering, salvations). Not an administrative return.
--   * `pastor_reports`      - `organization_id + content TEXT`. A placeholder
--                             with no structure and no workflow.
--   * a "Remit to HQ" button - a hardcoded 10% of tithes written as a negative
--                             ledger entry. No rate config, no approval, no
--                             record of who received it or for which period.
--
-- What a real church actually does, and what this models:
--
--   1. LOCAL CHURCH   the secretary fills the monthly/quarterly return for the
--                      period, including tithes, offerings and attendance.
--   2. SECRETARY      submits it to the pastor.
--   3. PASTOR         reviews it, may RETURN IT FOR CORRECTION, then approves.
--   4. PASTOR/BISHOP  submits the consolidated picture to HQ.
--   5. HQ             acknowledges, and the remittance becomes receivable.
--
-- Each step is enforced in a SECURITY DEFINER RPC, so a client cannot skip the
-- chain or approve its own return.
--
-- CUSTOM FIELDS
-- `report_templates.field_schema` holds the form definition as JSON, so a
-- conference can add fields (e.g. "Men's fellowship attendance", "Land and
-- buildings") without a code change or a migration. Standard operational and
-- financial figures are separate typed columns so they can be summed for HQ.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. TEMPLATES: the form definition, per conference and per report type
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.report_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL organisation = the platform default template every church falls back to.
  organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
  report_type TEXT NOT NULL CHECK (report_type IN ('monthly', 'quarterly')),
  name TEXT NOT NULL,
  description TEXT,

  -- Custom field definitions, e.g.
  --   [{"key":"mens_fellowship","label":"Men's fellowship attendance",
  --     "type":"number","required":false}, ...]
  -- Supported types: text | number | textarea | date | boolean | select
  field_schema JSONB NOT NULL DEFAULT '[]'::jsonb,

  -- Fraction of TITHE remitted to HQ. Configurable per conference because it
  -- is a governance decision, not a constant. 0.10 is the common default.
  remittance_rate NUMERIC(5,4) NOT NULL DEFAULT 0.10
    CHECK (remittance_rate >= 0 AND remittance_rate <= 1),

  -- Whether this template asks for the standard ops/financial block.
  include_financials BOOLEAN NOT NULL DEFAULT true,

  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_report_template_scope
  ON public.report_templates (
    COALESCE(organization_id, '00000000-0000-0000-0000-000000000000'::uuid),
    report_type)
  WHERE is_active;

-- ---------------------------------------------------------------------------
-- 2. SUBMISSIONS: one return per church per period
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.report_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  tenant_id TEXT NOT NULL,
  template_id UUID REFERENCES public.report_templates(id) ON DELETE SET NULL,

  report_type TEXT NOT NULL CHECK (report_type IN ('monthly', 'quarterly')),
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  -- Human label, e.g. "October 2026" or "Q3 2026". Denormalised so HQ lists do
  -- not need to rebuild it.
  period_label TEXT NOT NULL,

  -- draft -> submitted -> returned | approved -> submitted_hq -> acknowledged
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','submitted','returned','approved',
                      'submitted_hq','acknowledged')),

  -- Custom field answers, keyed by field_schema `key`.
  data JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Standard figures, typed so HQ can SUM them.
  tithe_total NUMERIC(14,2) NOT NULL DEFAULT 0,
  offering_total NUMERIC(14,2) NOT NULL DEFAULT 0,
  other_income_total NUMERIC(14,2) NOT NULL DEFAULT 0,
  attendance_total INT NOT NULL DEFAULT 0,
  new_members INT NOT NULL DEFAULT 0,
  baptisms INT NOT NULL DEFAULT 0,
  salvations INT NOT NULL DEFAULT 0,

  narrative TEXT,
  review_note TEXT,

  -- Chain of custody.
  prepared_by UUID REFERENCES public.profiles(id),          -- the secretary
  prepared_at TIMESTAMPTZ,
  submitted_by UUID REFERENCES public.profiles(id),
  submitted_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES public.profiles(id),          -- the pastor
  reviewed_at TIMESTAMPTZ,
  sent_hq_by UUID REFERENCES public.profiles(id),
  sent_hq_at TIMESTAMPTZ,
  acknowledged_by UUID REFERENCES public.profiles(id),
  acknowledged_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT report_period_order CHECK (period_end >= period_start)
);

-- One return per church per period. Re-submitting updates the same row rather
-- than creating duplicates.
CREATE UNIQUE INDEX IF NOT EXISTS ux_report_one_per_period
  ON public.report_submissions (tenant_id, report_type, period_start);

CREATE INDEX IF NOT EXISTS idx_report_org_status
  ON public.report_submissions (organization_id, status, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_report_tenant_period
  ON public.report_submissions (tenant_id, period_start DESC);

ALTER TABLE public.report_submissions ENABLE ROW LEVEL SECURITY;

-- A church sees its own returns; leadership of the church sees them too.
DROP POLICY IF EXISTS "report_read_own_tenant" ON public.report_submissions;
CREATE POLICY "report_read_own_tenant"
  ON public.report_submissions FOR SELECT
  USING (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
         IN ('superadmin','super_admin','coa_employee','employee')
    -- Organisation leadership (bishop / secretary / treasurer) sees every
    -- branch return, which is the whole point of the HQ step.
    OR EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = report_submissions.organization_id
         AND (o.bishop_id = auth.uid()
              OR o.secretary_id = auth.uid()
              OR o.treasurer_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
       WHERE p.id = auth.uid()
         AND p.role IN ('bishop','apostle','prophet')
         AND p.organization_id::text = report_submissions.organization_id::text
    )
  );

-- No INSERT/UPDATE/DELETE policy: every write goes through the workflow RPCs.

-- ---------------------------------------------------------------------------
-- 3. REMITTANCES: a real record, replacing the negative ledger entry
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.remittances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  -- NULL tenant = remitted to HQ / the conference itself.
  from_tenant_id TEXT,
  to_tenant_id TEXT,
  report_id UUID REFERENCES public.report_submissions(id) ON DELETE SET NULL,

  -- Quotable reference, e.g. RMT/ROC/2026/001. Treasurers read these aloud.
  reference TEXT NOT NULL,

  period_start DATE,
  period_end DATE,

  -- What it was computed from, so the 10% is explainable rather than magic.
  basis_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  rate NUMERIC(5,4) NOT NULL DEFAULT 0.10,
  amount NUMERIC(14,2) NOT NULL DEFAULT 0,

  -- pending -> in_transit -> received | rejected
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_transit','received','rejected')),

  sent_by UUID REFERENCES public.profiles(id),
  sent_at TIMESTAMPTZ,
  received_by UUID REFERENCES public.profiles(id),
  received_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_remittance_reference
  ON public.remittances (reference);
CREATE INDEX IF NOT EXISTS idx_remittance_org
  ON public.remittances (organization_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_remittance_from
  ON public.remittances (from_tenant_id, created_at DESC);

ALTER TABLE public.remittances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "remittance_read_parties" ON public.remittances;
CREATE POLICY "remittance_read_parties"
  ON public.remittances FOR SELECT
  USING (
    from_tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
         IN ('superadmin','super_admin','coa_employee','employee')
    OR EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = remittances.organization_id
         AND (o.bishop_id = auth.uid()
              OR o.treasurer_id = auth.uid()
              OR o.secretary_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- Reference sequences (human-quotable, like the transfer letters)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.next_report_reference(p_kind TEXT, p_org UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seq INT;
  v_code TEXT;
BEGIN
  SELECT COALESCE(next_id_sequence(p_kind || '_ref_' ||
           COALESCE(p_org::TEXT, 'platform')), '0001') INTO v_seq;

  SELECT UPPER(LEFT(REGEXP_REPLACE(COALESCE(o.name, 'COA'), '[^A-Za-z]', '', 'g'), 3))
    INTO v_code
    FROM (SELECT 1) d LEFT JOIN public.organizations o ON o.id = p_org;
  v_code := COALESCE(NULLIF(v_code, ''), 'COA');

  RETURN UPPER(LEFT(p_kind, 3)) || '/' || v_code || '/' ||
         TO_CHAR(now(), 'YYYY') || '/' || LPAD(v_seq::TEXT, 4, '0');
END;
$$;
REVOKE ALL ON FUNCTION public.next_report_reference(text, uuid) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- Resolve the template a church should use: its conference's, else the
-- platform default.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_report_template(
  p_org UUID, p_report_type TEXT
)
RETURNS UUID
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(
    (SELECT t.id FROM public.report_templates t
      WHERE t.report_type = p_report_type AND t.is_active
        AND (t.organization_id = p_org OR t.organization_id IS NULL)
      ORDER BY (t.organization_id IS NOT NULL) DESC
      LIMIT 1),
    NULL
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. WORKFLOW RPCs
-- ---------------------------------------------------------------------------

-- 4a. Secretary prepares / edits the return (draft or returned).
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
  v_row public.report_submissions;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_report_type NOT IN ('monthly','quarterly') THEN
    RAISE EXCEPTION 'unknown report type %', p_report_type;
  END IF;
  IF p_period_end < p_period_start THEN
    RAISE EXCEPTION 'the period end date is before the start date';
  END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    -- A secretary or any leader of THAT church may prepare its return.
    IF NOT public.is_tenant_leadership(p_tenant_id) THEN
      RAISE EXCEPTION 'only leadership of this church may file its return';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles
                    WHERE id = v_uid AND tenant_id::text = p_tenant_id) THEN
      RAISE EXCEPTION 'only someone in this church may file its return';
    END IF;
  END IF;

  SELECT c.organization_id INTO v_org
    FROM public.churches c WHERE c.tenant_id::text = p_tenant_id
       OR c.id::text = p_tenant_id
    LIMIT 1;

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

-- 4b. Pastor reviews: approves, or returns for correction.
CREATE OR REPLACE FUNCTION public.review_report(
  p_report_id UUID,
  p_approve BOOLEAN,
  p_note TEXT DEFAULT NULL
)
RETURNS public.report_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_org_off UUID;
  v_row public.report_submissions;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_row FROM public.report_submissions
   WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'return not found'; END IF;
  IF v_row.status NOT IN ('submitted','returned') THEN
    RAISE EXCEPTION 'this return is % and cannot be reviewed', v_row.status;
  END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    -- Leadership of the reporting church, or leadership of its conference.
    IF NOT public.is_tenant_leadership(v_row.tenant_id) THEN
      IF v_row.organization_id IS NULL THEN
        RAISE EXCEPTION 'only leadership of this church may review its return';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM public.organizations o
         WHERE o.id = v_row.organization_id
           AND (o.bishop_id = v_uid OR o.secretary_id = v_uid
                OR o.treasurer_id = v_uid)
      ) AND v_role NOT IN ('bishop','apostle','prophet') THEN
        RAISE EXCEPTION 'only the pastor or conference leadership may review this return';
      END IF;
    END IF;

    -- A reviewer must not be the person who prepared it.
    IF v_row.prepared_by = v_uid AND v_role NOT IN
         ('superadmin','super_admin','coa_employee','employee') THEN
      RAISE EXCEPTION 'a return cannot be reviewed by the person who prepared it';
    END IF;
  END IF;

  UPDATE public.report_submissions
     SET status = CASE WHEN p_approve THEN 'approved' ELSE 'returned' END,
         reviewed_by = v_uid,
         reviewed_at = now(),
         review_note = p_note,
         updated_at = now()
   WHERE id = p_report_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.review_report(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_report(uuid, boolean, text) TO authenticated;

-- 4c. Send the consolidated picture to HQ.
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

  -- Only APPROVED returns go up. An unapproved return must not reach HQ.
  UPDATE public.report_submissions
     SET status = 'submitted_hq',
         sent_hq_by = v_uid,
         sent_hq_at = now(),
         narrative = COALESCE(p_note, narrative),
         updated_at = now()
   WHERE organization_id = p_organization_id
     AND period_start = p_period_start
     AND period_end = p_period_end
     AND status = 'approved';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN QUERY SELECT v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.send_reports_to_hq(uuid, date, date, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_reports_to_hq(uuid, date, date, text)
  TO authenticated;

-- 4d. HQ acknowledges.
CREATE OR REPLACE FUNCTION public.acknowledge_reports(
  p_organization_id UUID,
  p_period_start DATE,
  p_period_end DATE,
  p_note TEXT DEFAULT NULL
)
RETURNS TABLE(ack_count INT)
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
         AND (o.bishop_id = v_uid OR o.secretary_id = v_uid
              OR o.treasurer_id = v_uid)
    ) AND v_role NOT IN ('bishop','apostle','prophet') THEN
      RAISE EXCEPTION 'only conference leadership may acknowledge returns';
    END IF;
  END IF;

  UPDATE public.report_submissions
     SET status = 'acknowledged',
         acknowledged_by = v_uid,
         acknowledged_at = now(),
         review_note = COALESCE(p_note, review_note),
         updated_at = now()
   WHERE organization_id = p_organization_id
     AND period_start = p_period_start
     AND period_end = p_period_end
     AND status = 'submitted_hq';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN QUERY SELECT v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.acknowledge_reports(uuid, date, date, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_reports(uuid, date, date, text)
  TO authenticated;

-- 4e. Raise a remittance from an approved return.
-- The rate comes from the template, so "10%" is configurable per conference
-- instead of hardcoded in the UI.
CREATE OR REPLACE FUNCTION public.raise_remittance(
  p_report_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS public.remittances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_r public.report_submissions;
  v_rate NUMERIC := 0.10;
  v_amount NUMERIC;
  v_row public.remittances;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_r FROM public.report_submissions WHERE id = p_report_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'return not found'; END IF;
  IF v_r.status NOT IN ('approved','submitted_hq','acknowledged') THEN
    RAISE EXCEPTION 'only an approved return can generate a remittance (this one is %)', v_r.status;
  END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF NOT public.is_tenant_leadership(v_r.tenant_id) THEN
      RAISE EXCEPTION 'only leadership of this church may remit';
    END IF;
  END IF;

  SELECT COALESCE(t.remittance_rate, 0.10) INTO v_rate
    FROM public.report_templates t
   WHERE t.id = v_r.template_id
      AND t.is_active;

  -- Basis is TITHE only, never total income: offerings are not remitted in the
  -- common case, and remitting them would be wrong.
  v_amount := ROUND(v_r.tithe_total * v_rate, 2);

  INSERT INTO public.remittances
    (organization_id, from_tenant_id, report_id, reference,
     period_start, period_end, basis_amount, rate, amount, status, sent_by,
     sent_at, note)
  VALUES
    (v_r.organization_id, v_r.tenant_id, p_report_id,
     public.next_report_reference('remittance', v_r.organization_id),
     v_r.period_start, v_r.period_end, v_r.tithe_total, v_rate, v_amount,
     'in_transit', v_uid, now(), p_note)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.raise_remittance(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.raise_remittance(uuid, text) TO authenticated;

-- 4f. HQ confirms money actually arrived.
CREATE OR REPLACE FUNCTION public.settle_remittance(
  p_remittance_id UUID,
  p_receive BOOLEAN,
  p_note TEXT DEFAULT NULL
)
RETURNS public.remittances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_row public.remittances;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT * INTO v_row FROM public.remittances
   WHERE id = p_remittance_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'remittance not found'; END IF;
  IF v_row.status IN ('received','rejected') THEN
    RAISE EXCEPTION 'this remittance is already %', v_row.status;
  END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = v_row.organization_id
         AND (o.bishop_id = v_uid OR o.treasurer_id = v_uid
              OR o.secretary_id = v_uid)
    ) AND v_role NOT IN ('bishop','apostle','prophet') THEN
      RAISE EXCEPTION 'only conference leadership may confirm a remittance';
    END IF;
  END IF;

  UPDATE public.remittances
     SET status = CASE WHEN p_receive THEN 'received' ELSE 'rejected' END,
         received_by = v_uid,
         received_at = now(),
         note = COALESCE(p_note, note),
         updated_at = now()
   WHERE id = p_remittance_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.settle_remittance(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.settle_remittance(uuid, boolean, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Audit both. A financial return and a remittance are exactly the records a
--    church disputes later.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['report_submissions','remittances'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_church_audit_%s ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_church_audit_%I
         AFTER INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture()', t, t);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Default monthly + quarterly templates, so the chain is usable immediately.
-- ---------------------------------------------------------------------------
INSERT INTO public.report_templates
  (organization_id, report_type, name, description, field_schema,
   remittance_rate, include_financials)
VALUES
  (NULL, 'monthly',
   'Monthly Church Return',
   'Standard monthly return: income, attendance and church life, submitted to the pastor then to conference HQ.',
   '[
     {"key":"prayer_meetings","label":"Prayer meetings held","type":"number","required":false},
     {"key":" bible_study","label":"Bible study attendance","type":"number","required":false},
     {"key":"womens_fellowship","label":"Women''s fellowship members","type":"number","required":false},
     {"key":"mens_fellowship","label":"Men''s fellowship members","type":"number","required":false},
     {"key":"youth_attendance","label":"Youth attendance","type":"number","required":false},
     {"key":"choir_members","label":"Choir / worship team members","type":"number","required":false},
     {"key":"usher_team","label":"Ushers on duty","type":"number","required":false},
     {"key":"house_fellowships","label":"House fellowships / cells","type":"number","required":false},
     {"key":"land_buildings","label":"Land and buildings owned","type":"textarea","required":false},
     {"key":"major_events","label":"Major events this month","type":"textarea","required":false},
     {"key":"challenges","label":"Challenges facing the church","type":"textarea","required":false},
     {"key":"prayer_requests","label":"Prayer requests for HQ","type":"textarea","required":false}
   ]'::jsonb,
   0.10, true),
  (NULL, 'quarterly',
   'Quarterly Church Return',
   'Consolidated quarter: income, attendance, membership and progress across all departments.',
   '[
     {"key":"quarter_theme","label":"Theme for the quarter","type":"text","required":false},
     {"key":"members_before","label":"Members at the start of the quarter","type":"number","required":true},
     {"key":"members_after","label":"Members at the end of the quarter","type":"number","required":true},
     {"key":"departments","label":"Departments and their leaders","type":"textarea","required":false},
     {"key":"property_status","label":"Property and equipment status","type":"textarea","required":false},
     {"key":"staff_needs","label":"Staffing needs","type":"textarea","required":false},
     {"key":"projects","label":"Projects this quarter","type":"textarea","required":false},
     {"key":"goals_next_quarter","label":"Goals for next quarter","type":"textarea","required":false},
     {"key":"issues_for_conference","label":"Matters for conference attention","type":"textarea","required":false}
   ]'::jsonb,
   0.10, true)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 7. Refuse to ship a broken chain.
-- ---------------------------------------------------------------------------
DO $$
DECLARE n INT;
BEGIN
  IF to_regclass('public.report_submissions') IS NULL
     OR to_regclass('public.remittances') IS NULL THEN
    RAISE EXCEPTION 'reporting tables were not created';
  END IF;

  SELECT count(*) INTO n FROM pg_proc
   WHERE proname IN ('save_report_draft','review_report','send_reports_to_hq',
                     'acknowledge_reports','raise_remittance','settle_remittance');
  IF n <> 6 THEN
    RAISE EXCEPTION 'expected 6 workflow functions, found %', n;
  END IF;

  -- Neither table may be writable directly, or the chain can be bypassed.
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN ('report_submissions','remittances')
       AND cmd IN ('INSERT','UPDATE','DELETE')
  ) THEN
    RAISE EXCEPTION 'reporting tables must be written only via their workflow RPCs';
  END IF;

  IF (SELECT count(*) FROM public.report_templates) < 2 THEN
    RAISE EXCEPTION 'the default monthly and quarterly templates are missing';
  END IF;
END;
$$;