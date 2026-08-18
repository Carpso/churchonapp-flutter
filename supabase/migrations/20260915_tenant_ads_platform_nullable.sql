-- 20260915 Platform ads may be tenant-less (platform-wide).
-- Superadmins create ads shown on all churches; tenant_id is optional.

ALTER TABLE tenant_ads ALTER COLUMN tenant_id DROP NOT NULL;