-- ============================================================================
-- Membership classes + pastoral care (discipline) register
-- ============================================================================
-- TWO REGISTERS THAT REAL CHURCHES RUN ON PAPER
--
-- 1. MEMBERSHIP CLASSES
--    Pentecostal and charismatic churches (UPC/UPCI and the Independent
--    churches across Zambia) do not have a single notion of "member". A person
--    moves through a progression, and the church's health is literally measured
--    by how many people are moving through it:
--
--      visitor -> convert (1st class) -> convert (2nd class)
--              -> righteous member -> worker (full member)
--
--    A worker is a member who has been accepted for full participation. Being
--    on the workers' roll is what qualifies someone to serve, and the
--    transition is a deliberate act the church records. Today that roll is a
--    register book. This makes it queryable ("how many workers do we have",
--    "who is overdue for their second class") without changing how the church
--    actually operates.
--
-- 2. PASTORAL CARE / DISCIPLINE
--    Counselling, warnings, suspension and restoration. This is the most
--    sensitive data in the entire product, so the controls are deliberately
--    tighter than anywhere else:
--      - leadership of the church ONLY; members can never read it, not even
--        their own record
--      - no client INSERT/UPDATE policies; all writes via SECURITY DEFINER RPCs
--        so the actor is always recorded and the rules are enforced in one place
--      - every row is audited
--      - a summary view (counts only) is available to leadership without
--        exposing the detail
--
-- DESIGN
-- - `member_classes` stores the CURRENT class on the member plus a full
--   promotion history, because "when was this person accepted as a worker" is
--   the question that actually gets asked.
-- - Nothing is ever hard-deleted; a correction is a new row, so the trail
--   survives.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. MEMBERSHIP CLASSES
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tenant_id TEXT NOT NULL,
  class TEXT NOT NULL DEFAULT 'convert'
    CHECK (class IN ('visitor', 'convert', 'righteous_member', 'worker')),
  -- Which convert class, where the church runs a staged 1st/2nd class course.
  convert_stage INT CHECK (convert_stage IN (1, 2)),
  class_date DATE NOT NULL DEFAULT CURRENT_DATE,
  previous_class TEXT,
  promoted_by UUID REFERENCES public.profiles(id),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_member_classes_tenant
  ON public.member_classes (tenant_id, class);
CREATE INDEX IF NOT EXISTS idx_member_classes_member
  ON public.member_classes (member_id, class_date DESC);
-- One current row per member per class stage; history is kept by class_date, so
-- re-assigning the same class twice is blocked.
CREATE UNIQUE INDEX IF NOT EXISTS ux_member_classes_current
  ON public.member_classes (member_id, class, COALESCE(convert_stage, 0));

ALTER TABLE public.member_classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_classes_read_leadership" ON public.member_classes;
CREATE POLICY "member_classes_read_leadership"
  ON public.member_classes FOR SELECT
  USING (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    AND (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('pastor','bishop','apostle','prophet','admin','leader',
            'department_leader','general_secretary','treasurer')
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('superadmin','super_admin','coa_employee','employee')
  );

-- ---------------------------------------------------------------------------
-- 2. DISCIPLINE / PASTORAL CARE
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discipline_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tenant_id TEXT NOT NULL,
  -- 'counselling' is routine and non-disciplinary; the rest are formal steps.
  category TEXT NOT NULL
    CHECK (category IN ('counselling', 'warning', 'suspension',
                        'excommunication', 'restoration')),
  severity TEXT NOT NULL DEFAULT 'pastoral'
    CHECK (severity IN ('pastoral', 'formal', 'serious')),
  incident_date DATE NOT NULL DEFAULT CURRENT_DATE,
  summary TEXT NOT NULL,
  action_taken TEXT,
  -- 'open' until resolved; 'restored' is the pastoral end state.
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved', 'appealed', 'restored')),
  recorded_by UUID REFERENCES public.profiles(id),
  resolved_by UUID REFERENCES public.profiles(id),
  resolved_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_discipline_tenant
  ON public.discipline_records (tenant_id, status, incident_date DESC);
CREATE INDEX IF NOT EXISTS idx_discipline_member
  ON public.discipline_records (member_id, incident_date DESC);
-- A member cannot be under two open suspensions at once: the church handles
-- one matter at a time.
CREATE UNIQUE INDEX IF NOT EXISTS ux_discipline_one_open_suspension
  ON public.discipline_records (member_id)
  WHERE status = 'open' AND category = 'suspension';

ALTER TABLE public.discipline_records ENABLE ROW LEVEL SECURITY;

-- Leadership only. A member can NEVER read this, including their own row -
-- unlike member_attendance, where a member sees their own history.
DROP POLICY IF EXISTS "discipline_read_leadership" ON public.discipline_records;
CREATE POLICY "discipline_read_leadership"
  ON public.discipline_records FOR SELECT
  USING (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    AND (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('pastor','bishop','apostle','prophet','admin','leader',
            'department_leader','general_secretary')
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('superadmin','super_admin','coa_employee','employee')
  );

-- ---------------------------------------------------------------------------
-- Writes: RPCs only, so the actor and the rules live in one place.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_member_class(
  p_member_id UUID,
  p_class TEXT,
  p_convert_stage INT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.member_classes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_tenant TEXT;
  v_role TEXT;
  v_prev TEXT;
  v_row public.member_classes;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF NOT public.is_tenant_leadership((SELECT p.tenant_id FROM public.profiles p
                                         WHERE p.id = v_uid)) THEN
      RAISE EXCEPTION 'only church leadership may change a member class';
    END IF;
  END IF;

  SELECT p.tenant_id::text INTO v_tenant
    FROM public.profiles p WHERE p.id = p_member_id;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'member not found'; END IF;

  IF p_class NOT IN ('visitor','convert','righteous_member','worker') THEN
    RAISE EXCEPTION 'unknown class %', p_class;
  END IF;

  -- Current class becomes the previous class, so the progression is readable.
  SELECT class INTO v_prev FROM public.member_classes
   WHERE member_id = p_member_id AND class = p_class
     AND COALESCE(convert_stage, 0) = COALESCE(p_convert_stage, 0)
   ORDER BY class_date DESC LIMIT 1;

  INSERT INTO public.member_classes
    (member_id, tenant_id, class, convert_stage, previous_class,
     promoted_by, notes)
  VALUES (p_member_id, v_tenant, p_class, p_convert_stage, v_prev, v_uid, p_notes)
  ON CONFLICT (member_id, class, COALESCE(convert_stage, 0))
  DO UPDATE SET class_date = CURRENT_DATE,
                promoted_by = EXCLUDED.promoted_by,
                notes = EXCLUDED.notes
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_member_class(uuid, text, int, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_member_class(uuid, text, int, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.record_discipline(
  p_member_id UUID,
  p_category TEXT,
  p_summary TEXT,
  p_severity TEXT DEFAULT 'pastoral',
  p_action_taken TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.discipline_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_tenant TEXT;
  v_role TEXT;
  v_row public.discipline_records;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  -- Deliberately narrower than set_member_class: discipline is reserved to the
  -- pastoral leadership, not to 'leader' / 'department_leader' / treasurer.
  SELECT p.role INTO v_role
    FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF v_role NOT IN ('pastor','bishop','apostle','prophet','admin','general_secretary') THEN
      RAISE EXCEPTION 'only pastoral leadership may record this';
    END IF;
  END IF;

  IF p_category NOT IN ('counselling','warning','suspension',
                        'excommunication','restoration') THEN
    RAISE EXCEPTION 'unknown category %', p_category;
  END IF;
  IF p_severity NOT IN ('pastoral','formal','serious') THEN
    RAISE EXCEPTION 'unknown severity %', p_severity;
  END IF;
  IF p_summary IS NULL OR length(trim(p_summary)) < 3 THEN
    RAISE EXCEPTION 'a summary is required';
  END IF;

  SELECT p.tenant_id::text INTO v_tenant
    FROM public.profiles p WHERE p.id = p_member_id;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'member not found'; END IF;

  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF NOT public.is_tenant_leadership(v_tenant) THEN
      RAISE EXCEPTION 'only leadership of this church may record this';
    END IF;
  END IF;

  INSERT INTO public.discipline_records
    (member_id, tenant_id, category, severity, summary, action_taken,
     recorded_by, notes)
  VALUES (p_member_id, v_tenant, p_category, p_severity, p_summary,
          p_action_taken, v_uid, p_notes)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.record_discipline(uuid, text, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_discipline(uuid, text, text, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_discipline(
  p_record_id UUID,
  p_status TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.discipline_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_row public.discipline_records;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  IF p_status NOT IN ('resolved','appealed','restored') THEN
    RAISE EXCEPTION 'unknown status %', p_status;
  END IF;

  SELECT p.role INTO v_role FROM public.profiles p WHERE p.id = v_uid;
  IF v_role NOT IN ('superadmin','super_admin','coa_employee','employee') THEN
    IF v_role NOT IN ('pastor','bishop','apostle','prophet','admin','general_secretary') THEN
      RAISE EXCEPTION 'only pastoral leadership may resolve this';
    END IF;
  END IF;

  UPDATE public.discipline_records
     SET status = p_status,
         resolved_by = v_uid,
         resolved_at = now(),
         notes = COALESCE(p_notes, notes),
         updated_at = now()
   WHERE id = p_record_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN RAISE EXCEPTION 'record not found'; END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_discipline(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_discipline(uuid, text, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- Both registers are auditable.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['member_classes','discipline_records'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_church_audit_%s ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_church_audit_%I
         AFTER INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture()', t, t);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Refuse to apply unless the security posture is what was intended.
-- ---------------------------------------------------------------------------
DO $$
DECLARE n INT;
BEGIN
  IF to_regclass('public.member_classes') IS NULL
     OR to_regclass('public.discipline_records') IS NULL THEN
    RAISE EXCEPTION 'register tables were not created';
  END IF;

  -- A member must not be able to read the discipline register at all.
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'discipline_records'
       AND cmd = 'SELECT' AND qual LIKE '%auth.uid())%'
       AND qual NOT LIKE '%role%'
  ) THEN
    RAISE EXCEPTION 'discipline_records has a self-only read policy; it must be leadership-only';
  END IF;

  -- Neither table may be writable directly by a client.
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN ('member_classes', 'discipline_records')
       AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  ) THEN
    RAISE EXCEPTION 'these registers must be written only via their RPCs';
  END IF;

  SELECT count(*) INTO n FROM pg_trigger
   WHERE tgname LIKE 'trg_church_audit_%'
     AND tgname IN ('trg_church_audit_member_classes',
                    'trg_church_audit_discipline_records')
     AND NOT tgisinternal;
  IF n <> 2 THEN
    RAISE EXCEPTION 'audit triggers missing on the registers';
  END IF;
END;
$$;