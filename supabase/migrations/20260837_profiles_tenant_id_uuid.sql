-- ════════════════════════════════════════════════════════════════
-- CONVERT profiles.tenant_id FROM text TO uuid
-- Enables FK constraint to tenants(id) for referential integrity
-- All operations wrapped in safe blocks for idempotent re-run
-- ════════════════════════════════════════════════════════════════

DO $$ BEGIN
  -- 1. Only proceed if tenant_id is still text type
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
    AND column_name = 'tenant_id' AND data_type IN ('text', 'character varying', 'character')
  ) THEN
    -- Add new UUID column
    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id_new UUID;

    -- Copy valid UUID values from old text column
    UPDATE public.profiles
    SET tenant_id_new = tenant_id::UUID
    WHERE tenant_id IS NOT NULL
      AND tenant_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

    -- Drop old text column
    ALTER TABLE public.profiles DROP COLUMN IF EXISTS tenant_id;

    -- Rename new column to tenant_id
    ALTER TABLE public.profiles RENAME COLUMN tenant_id_new TO tenant_id;

    -- Add FK constraint to tenants table
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_tenant_id_fk
      FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)
      ON DELETE SET NULL;
  END IF;
END $$;