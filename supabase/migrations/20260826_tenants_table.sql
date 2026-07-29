-- ═══════════════════════════════════════════════════════════════
-- Create tenants table (parent of churches + future bookshops)
-- tenant_id = generic tenant FK (church/bookshop)
-- church_id = church-specific FK (nullable)
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Create tenants table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'church' CHECK (type IN ('church', 'bookshop')),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

-- Everyone can read tenants; only superadmin can insert/update
DO $$ BEGIN
  CREATE POLICY "tenants_select" ON public.tenants FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "tenants_insert" ON public.tenants FOR INSERT WITH CHECK (
    auth.jwt() -> 'app_metadata' ->> 'role' IN ('superadmin', 'super_admin')
    OR auth.jwt() -> 'user_metadata' ->> 'role' IN ('superadmin', 'super_admin')
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "tenants_update" ON public.tenants FOR UPDATE USING (
    auth.jwt() -> 'app_metadata' ->> 'role' IN ('superadmin', 'super_admin')
    OR auth.jwt() -> 'user_metadata' ->> 'role' IN ('superadmin', 'super_admin')
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2. Seed from existing churches ──────────────────────────────
INSERT INTO public.tenants (id, name, type, created_at)
SELECT id, name, 'church', created_at
FROM public.churches
ON CONFLICT (id) DO NOTHING;

-- ── 3. Add tenant_id to churches + FK to tenants ────────────────
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);

-- Populate tenant_id with same UUID as id for existing rows
UPDATE public.churches SET tenant_id = id WHERE tenant_id IS NULL;

-- Make tenant_id NOT NULL going forward
ALTER TABLE IF EXISTS public.churches ALTER COLUMN tenant_id SET NOT NULL;

-- ── 4. Re-point all tenant_id FKs from churches → tenants ───────
-- Only for tables where tenant_id is UUID type (text columns can't FK to uuid)

DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT con.conname, con.conrelid::regclass::text AS tbl
    FROM pg_constraint con
    JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_type t ON a.atttypid = t.oid
    WHERE con.contype = 'f'
      AND con.connamespace = 'public'::regnamespace
      AND con.confrelid = 'churches'::regclass
      AND t.typname = 'uuid'
  LOOP
    EXECUTE format('ALTER TABLE IF EXISTS public.%I DROP CONSTRAINT IF EXISTS %I', rec.tbl, rec.conname);
    EXECUTE format('ALTER TABLE IF EXISTS public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)', rec.tbl, rec.conname);
  END LOOP;
END $$;

-- Tables with text-typed tenant_id (e.g. profiles) can't have a UUID FK.
-- Those are left as-is; they reference churches(id) as text values for now.
-- Future migration: convert column type to UUID and add FK.

-- ── 5. Verify ───────────────────────────────────────────────────
SELECT 'tenants' AS table_name, COUNT(*) AS row_count FROM public.tenants
UNION ALL
SELECT 'churches_with_tenant_id' AS table_name, COUNT(*) FROM public.churches WHERE tenant_id IS NOT NULL;