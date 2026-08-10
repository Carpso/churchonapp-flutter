-- ═══════════════════════════════════════════════════════════════════════════════
-- UNLIMITED DATA IMPORT SYSTEM
-- Generic, secure import of members/contributions/events/ministries from CSV,
-- JSON, documents, and 3rd-party ChMS systems (Breeze, Planning Center, Rock,
-- FellowshipOne, etc.). Tenant-scoped + leadership-only on mutations.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Import templates (per-tenant presets: Breeze, Planning Center, RockRMS, ...)
CREATE TABLE IF NOT EXISTS public.import_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    entity_type TEXT NOT NULL,                 -- profiles | transactions | events | ministries | service_reports
    system_name TEXT,                          -- breeze | planning_center | rockrms | mtnbank | custom
    mappings JSONB NOT NULL DEFAULT '{}'::jsonb, -- { "sourceColumn": "targetColumn", ... }
    conflict_on TEXT,                          -- target column used for upsert dedup (e.g. phone_number)
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (tenant_id, name, entity_type)
);
CREATE INDEX IF NOT EXISTS idx_import_templates_tenant ON public.import_templates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_import_templates_entity ON public.import_templates(entity_type);

-- 2. Import log (immutable audit trail)
CREATE TABLE IF NOT EXISTS public.data_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    source_system TEXT,
    file_name TEXT,
    conflict_on TEXT,
    status TEXT NOT NULL DEFAULT 'pending',   -- pending | processing | completed | failed
    total_rows INT DEFAULT 0,
    imported_rows INT DEFAULT 0,
    failed_rows INT DEFAULT 0,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_data_imports_tenant ON public.data_imports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_data_imports_created ON public.data_imports(created_at DESC);

-- 3. Per-row import errors (auditable, re-downloadable)
CREATE TABLE IF NOT EXISTS public.import_errors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data_import_id UUID NOT NULL REFERENCES public.data_imports(id) ON DELETE CASCADE,
    row_number INT NOT NULL,
    payload JSONB,
    errors JSONB NOT NULL,                     -- [{column, message}]
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_import_errors_import ON public.import_errors(data_import_id);

-- 4. RLS — tenant-scoped access
ALTER TABLE public.import_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_errors ENABLE ROW LEVEL SECURITY;

-- import_templates: own tenant + leadership
CREATE POLICY "Leadership read own-tenant import templates"
    ON public.import_templates FOR SELECT TO authenticated
    USING (
        tenant_id IS NULL -- network-wide templates (COA managed)
        OR EXISTS (SELECT 1 FROM public.profiles p
                   WHERE p.id = auth.uid()
                     AND p.tenant_id::uuid = import_templates.tenant_id
                     AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin'))
    );
CREATE POLICY "Leadership manage own-tenant import templates"
    ON public.import_templates FOR ALL TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid()
                  AND p.tenant_id::uuid = import_templates.tenant_id
                  AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin'))
    )
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid()
                  AND (p.role IN ('superadmin','coa_employee')
                       OR p.tenant_id::uuid = import_templates.tenant_id)
                  AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin'))
    );

-- data_imports: leadership audit read
CREATE POLICY "Leadership read own-tenant imports"
    ON public.data_imports FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid()
                  AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin')
                  AND (p.role IN ('superadmin','coa_employee')
                       OR p.tenant_id::uuid = data_imports.tenant_id))
    );
CREATE POLICY "Leadership create imports for own tenant"
    ON public.data_imports FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid()
                  AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin')
                  AND (p.role IN ('superadmin','coa_employee')
                       OR p.tenant_id::uuid = data_imports.tenant_id))
    );

-- import_errors: readable by leadership of the import's tenant
CREATE POLICY "Leadership read own-tenant import errors"
    ON public.import_errors FOR SELECT TO authenticated
    USING (
        EXISTS (
          SELECT 1 FROM public.data_imports di
          JOIN public.profiles p ON p.id = auth.uid()
          WHERE di.id = import_errors.data_import_id
            AND p.role IN ('superadmin','coa_employee','bishop','general_secretary','pastor','admin')
            AND (p.role IN ('superadmin','coa_employee')
                 OR p.tenant_id::uuid = di.tenant_id))
    );
CREATE POLICY "System (function) writes import errors for own tenant"
    ON public.import_errors FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.data_imports di
          JOIN public.profiles p ON p.id = auth.uid()
          WHERE di.id = import_errors.data_import_id
            AND p.role IN ('superadmin','coa_employee')
            AND (p.tenant_id::uuid = di.tenant_id OR p.role = 'superadmin'))
    );

COMMENT ON TABLE public.import_templates IS 'Per-tenant column-mapping presets for CSV/JSON/ChMS imports';
COMMENT ON TABLE public.data_imports IS 'Audit trail of every import job';
COMMENT ON TABLE public.import_errors IS 'Per-row import failures (auditable)';

-- 5. Server-side column validator. Enforces the sensitive-column blocklist
-- (role/coins/balance escalation) and existence checks — the Edge Function consults
-- this before any upsert so the security boundary lives in the database.
CREATE OR REPLACE FUNCTION public.sp_validate_import_columns(
    p_table TEXT,
    p_columns TEXT[]
)
RETURNS TABLE (column_name TEXT, valid BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    forbidden TEXT[] := ARRAY[
        'role','coins','streak_count','balance_cc','balance_zmw',
        'is_work_mode','password_hash','email','created_at','updated_at'
    ];
    col TEXT;
BEGIN
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
$$;
REVOKE EXECUTE ON FUNCTION public.sp_validate_import_columns(TEXT, TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.sp_validate_import_columns(TEXT, TEXT[]) TO authenticated;
