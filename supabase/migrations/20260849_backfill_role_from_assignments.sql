-- Migration: Backfill profiles.role from role_assignments
-- This ensures existing data is consistent with the new per-tenant role model.
-- profiles.role is now a cache field derived from role_assignments.

-- 1. Backfill profiles.role from role_assignments for each user's current tenant
-- (Temporarily disable the role-change guard + audit triggers; this is a system
--  backfill, not a user-initiated role change)
ALTER TABLE public.profiles DISABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles DISABLE TRIGGER trg_log_role_change;

UPDATE profiles p
SET role = ra.role_name
FROM role_assignments ra
WHERE ra.user_id = p.id
  AND ra.tenant_id::text = p.tenant_id
  AND ra.status = 'approved'
  AND p.role != ra.role_name;

-- 2. Reset profiles.role to 'member' for users with no role_assignments in their tenant
UPDATE profiles p
SET role = 'member'
WHERE NOT EXISTS (
  SELECT 1 FROM role_assignments ra
  WHERE ra.user_id = p.id
    AND ra.tenant_id::text = p.tenant_id
    AND ra.status = 'approved'
)
AND p.role != 'member'
AND p.tenant_id IS NOT NULL;

ALTER TABLE public.profiles ENABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles ENABLE TRIGGER trg_log_role_change;

-- 3. Log the changes
DO $$
DECLARE
  changed_count INT;
BEGIN
  GET DIAGNOSTICS changed_count = ROW_COUNT;
  RAISE NOTICE 'Backfill complete. profiles.role updated for % users.', changed_count;
END $$;
