-- Backfill role_assignments from profiles.role for users who registered before
-- the audit trail system was fully implemented. One-time migration, idempotent.
INSERT INTO public.role_assignments (user_id, role_name, tenant_id, assigned_by, status, created_at)
SELECT
  p.id AS user_id,
  p.role,
  p.tenant_id::uuid,
  p.id AS assigned_by,
  'approved'::text AS status,
  coalesce(p.created_at, now()) AS created_at
FROM public.profiles p
WHERE p.role IS NOT NULL
  AND p.role <> 'member'
  AND p.tenant_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.role_assignments ra
    WHERE ra.user_id = p.id
      AND ra.role_name = p.role
      AND ra.tenant_id::text = p.tenant_id
  );
