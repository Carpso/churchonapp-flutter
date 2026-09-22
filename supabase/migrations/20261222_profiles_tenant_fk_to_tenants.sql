-- ============================================================================
-- 20261222 — profiles tenant FK: point the UUID mirror at `tenants`, not `churches`
--
-- ROOT CAUSE (Bug 1): `profiles.tenant_id` is a GENERIC tenant reference that may
-- be a church OR a bookshop. Migration 20260837 added a mirror column
-- `profiles.tenant_id_uuid` with FK `profiles_tenant_id_uuid_fkey` pointing at
-- `churches(id)`, plus a BEFORE INSERT/UPDATE trigger (`trg_profiles_tenant_sync`)
-- that copies `tenant_id -> tenant_id_uuid`. Selecting a bookshop tenant then
-- fails on the profile write:
--   ERROR: 23503 insert or update on table "profiles" violates foreign key
--   constraint "profiles_tenant_id_uuid_fkey"  (Key is not present in "churches")
-- because a bookshop id lives in `tenants`/`bookshops`, never in `churches`.
--
-- FIX: repoint the FK at `tenants(id)` (the parent of BOTH churches and
-- bookshops). The `tenant_id_uuid` column is already `uuid`, matching
-- `tenants.id`, so no type alignment is needed. Any stale value that is not a
-- tenant is cleared first so the constraint validates.
-- ============================================================================

-- 1. Clear any tenant_id_uuid value that is not present in tenants (legacy /
--    dangling rows) so the re-pointed constraint validates.
UPDATE public.profiles p
   SET tenant_id_uuid = NULL
 WHERE p.tenant_id_uuid IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id = p.tenant_id_uuid);

-- 2. Drop-and-recreate the constraint against tenants(id). Idempotent guard.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_tenant_id_uuid_fkey;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_tenant_id_uuid_fkey
  FOREIGN KEY (tenant_id_uuid) REFERENCES public.tenants(id) ON DELETE SET NULL;

-- 3. Make the sync trigger keep BOTH uuid mirrors aligned (tenant_uuid already
--    references tenants(id); tenant_id_uuid now does too). This means a
--    bookshop selection round-trips without touching a church FK.
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
      NEW.tenant_uuid := NEW.tenant_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      NULL; -- skip non-UUID tenant_id values (legacy text ids)
    END;
  END IF;
  RETURN NEW;
END;
$$;

-- Verify (informational; deploy output only).
SELECT 'profiles_tenant_id_uuid_fkey -> tenants' AS check_name,
       pg_get_constraintdef(c.oid) AS definition
  FROM pg_constraint c
 WHERE c.conname = 'profiles_tenant_id_uuid_fkey';
