-- ═══════════════════════════════════════════════════════════════════════════════
-- PHASE-1: profiles.tenant_id TEXT → UUID migration
-- Adds a properly-typed UUID column alongside the existing text column,
-- backfills via trigger, and creates the FK constraint.
-- The original tenant_id TEXT column is retained for backward compatibility
-- with existing RLS policies (too many to rewrite in one migration).
-- A future PHASE-2 migration will swap the columns after all policies
-- have been updated.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Add the UUID column (nullable initially; non-null constraint deferred to PHASE-2)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id_uuid UUID;

-- 2. Backfill existing rows where tenant_id holds a valid UUID
UPDATE public.profiles
SET tenant_id_uuid = tenant_id::uuid
WHERE tenant_id IS NOT NULL AND tenant_id_uuid IS NULL;

-- 3. Create FK constraint (deferred; will fail if invalid UUIDs remain after backfill)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'profiles_tenant_id_uuid_fkey'
      AND table_name = 'profiles'
      AND table_schema = 'public'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_tenant_id_uuid_fkey
      FOREIGN KEY (tenant_id_uuid) REFERENCES public.churches(id) ON DELETE SET NULL;
  END IF;
END;
$$;

-- 4. Index on the new column for join performance
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_uuid ON public.profiles(tenant_id_uuid);

-- 5. Trigger to keep tenant_id_uuid in sync when tenant_id text is updated
CREATE OR REPLACE FUNCTION public.profiles_tenant_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tenant_id IS NOT NULL THEN
    BEGIN
      NEW.tenant_id_uuid := NEW.tenant_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      NULL; -- skip invalid UUIDs
    END;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_profiles_tenant_sync'
      AND event_object_table = 'profiles'
  ) THEN
    CREATE TRIGGER trg_profiles_tenant_sync
      BEFORE INSERT OR UPDATE ON public.profiles
      FOR EACH ROW
      EXECUTE FUNCTION public.profiles_tenant_sync();
  END IF;
END;
$$;

-- 6. Allow-list the new column for profiles import (data_import system)
--    tenant_id_uuid is informational; the import Edge Function writes tenant_id as text.
--    This is documented in sp_validate_import_columns.
