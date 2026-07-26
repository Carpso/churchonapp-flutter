-- ════════════════════════════════════════════════════════════════
-- CONVERT profiles.tenant_id FROM text TO uuid
-- Enables FK constraint to tenants(id) for referential integrity
-- ════════════════════════════════════════════════════════════════

-- 1. Add new UUID column
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id_new UUID;

-- 2. Copy valid UUID values from old text column
UPDATE public.profiles
SET tenant_id_new = tenant_id::UUID
WHERE tenant_id IS NOT NULL
  AND tenant_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

-- 3. Drop old text column
ALTER TABLE public.profiles DROP COLUMN IF EXISTS tenant_id;

-- 4. Rename new column to tenant_id
ALTER TABLE public.profiles RENAME COLUMN tenant_id_new TO tenant_id;

-- 5. Add FK constraint to tenants table
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_tenant_id_fk
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)
  ON DELETE SET NULL;

-- 6. Make tenant_id NOT NULL for existing rows that have a valid tenant
-- (Leave nullable for now to handle any edge cases)
-- ALTER TABLE public.profiles ALTER COLUMN tenant_id SET NOT NULL;