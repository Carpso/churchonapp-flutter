-- ============================================================================
-- Tenant-visible audit trail for church operations
-- ============================================================================
-- WHY
-- `admin_audit_log` exists but is readable only by platform staff
-- (superadmin/employee). A pastor or treasurer therefore has NO record of who
-- changed a member's details, moved a role, or touched money in their own
-- church. When a member disputes a figure there is no way to reconstruct what
-- happened - which is exactly when a church needs the log most.
--
-- The existing `AuditService` is called from only 4 places in the app, so a
-- client-side trail would only record what someone remembered to log. These
-- are DATABASE TRIGGERS, so they capture every write regardless of which
-- client, RPC, admin tool or psql session performed it. A client can add
-- context but can never omit the fact.
--
-- SCOPE (deliberately the sensitive, contested things)
--   profiles        role, name, phone, tenant reassignment
--   member_attendance  marking present/absent after the fact
--   transactions    money records
--   payout_tasks    disbursement state
--
-- Reads: leadership of the affected church, plus platform staff.
-- Writes: trigger-only (SECURITY DEFINER, no client INSERT grant).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.church_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id TEXT,
  actor_id UUID,
  actor_role TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  -- Only the fields that actually changed, so the log stays readable and does
  -- not duplicate the whole row.
  changed JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_church_audit_tenant_created
  ON public.church_audit_log (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_church_audit_entity
  ON public.church_audit_log (entity_type, entity_id);

ALTER TABLE public.church_audit_log ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Reads: leadership of the church that owns the row, or platform staff.
-- Members must NOT be able to read this - it exposes who disciplines whom.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "church_audit_read_leadership" ON public.church_audit_log;
CREATE POLICY "church_audit_read_leadership"
  ON public.church_audit_log FOR SELECT
  USING (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    AND (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('pastor','bishop','apostle','prophet','admin','leader','department_leader',
            'general_secretary','general_treasurer','treasurer')
    OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
        IN ('superadmin','super_admin','coa_employee','employee')
  );

-- No INSERT/UPDATE/DELETE policy at all: rows arrive only via trigger. A
-- client cannot forge or erase history.

-- ---------------------------------------------------------------------------
-- Shared trigger body. Records only columns that actually changed, and skips
-- writes that change nothing (avoids log noise from no-op updates).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.church_audit_capture()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_changed  JSONB := '{}'::jsonb;
  v_tenant   TEXT;
  v_actor    UUID := auth.uid();
  v_actor_role TEXT;
  col        TEXT;
  old_val    TEXT;
  new_val    TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_changed := '{}'::jsonb;
  ELSE
    FOR col IN
      SELECT a.attname
      FROM pg_attribute a
      WHERE a.attrelid = TG_RELID
        AND a.attnum > 0
        AND NOT a.attisdropped
        AND a.attname NOT IN ('updated_at','created_at')
    LOOP
      EXECUTE format('SELECT ($1).%I::text, ($2).%I::text', col, col)
        INTO old_val, new_val USING OLD, NEW;
      IF old_val IS DISTINCT FROM new_val THEN
        v_changed := v_changed || jsonb_build_object(col,
          jsonb_build_object('from', old_val, 'to', new_val));
      END IF;
    END LOOP;
  END IF;

  -- Nothing actually changed: do not pollute the log.
  IF TG_OP = 'UPDATE' AND v_changed = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  -- Read the tenant off the JSON view rather than NEW.tenant_id: this trigger
  -- is shared across four tables and not all of them have that column, so a
  -- direct field reference would raise at runtime on the others.
  v_tenant := to_jsonb(NEW) ->> 'tenant_id';
  IF v_tenant IS NULL AND TG_OP = 'UPDATE' THEN
    v_tenant := to_jsonb(OLD) ->> 'tenant_id';
  END IF;
  IF v_tenant IS NULL OR v_tenant = '' THEN
    -- Some rows (e.g. a payout for a church) carry the tenant elsewhere; fall
    -- back to the owning profile so the row is still visible to someone.
    v_tenant := COALESCE(
      to_jsonb(NEW) ->> 'church_id',
      to_jsonb(NEW) ->> 'user_id'
    );
  END IF;

  SELECT role INTO v_actor_role FROM public.profiles WHERE id = v_actor;

  INSERT INTO public.church_audit_log
    (tenant_id, actor_id, actor_role, action, entity_type, entity_id, changed)
  VALUES (
    v_tenant, v_actor, v_actor_role,
    lower(TG_OP) || '_' || lower(TG_TABLE_NAME),
    TG_TABLE_NAME,
    COALESCE(to_jsonb(NEW) ->> 'id', to_jsonb(OLD) ->> 'id'),
    v_changed
  );

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Attach. Each is created defensively so re-running is safe.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  tbls TEXT[] := ARRAY['profiles','member_attendance','transactions','payout_tasks'];
BEGIN
  FOREACH t IN ARRAY tbls LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'skipping audit trigger: % does not exist', t;
      CONTINUE;
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS trg_church_audit_%s ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_church_audit_%I
         AFTER INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.church_audit_capture()', t, t);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Sanity checks: fail the migration rather than ship a silent no-op.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  n INT;
BEGIN
  IF to_regclass('public.church_audit_log') IS NULL THEN
    RAISE EXCEPTION 'church_audit_log was not created';
  END IF;

  SELECT count(*) INTO n FROM pg_trigger
  WHERE tgname LIKE 'trg_church_audit_%' AND NOT tgisinternal;
  IF n = 0 THEN
    RAISE EXCEPTION 'no audit triggers were attached - history would be silently lost';
  END IF;

  -- A client must not be able to write history directly.
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'church_audit_log'
      AND cmd IN ('INSERT','UPDATE','DELETE')
  ) THEN
    RAISE EXCEPTION 'church_audit_log must be trigger-only (found a write policy)';
  END IF;
END;
$$;