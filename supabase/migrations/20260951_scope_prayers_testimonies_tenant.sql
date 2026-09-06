-- 20260951 — Tenant-scope prayers + testimonies
--
-- Both tables previously had SELECT policies of USING (true) — every
-- authenticated user could read every church's prayer requests (names,
-- content, ai_encouragement) and testimonies platform-wide. This adds a
-- tenant_id column (backfilled from each author's profile tenant), replaces
-- the loose SELECT/INSERT policies with tenant-scoped ones, and keeps a
-- staff moderation override via is_admin_or_employee().

ALTER TABLE public.prayers ADD COLUMN IF NOT EXISTS tenant_id uuid;
ALTER TABLE public.testimonies ADD COLUMN IF NOT EXISTS tenant_id uuid;

-- Backfill from author profiles (profiles.tenant_id is text)
UPDATE public.prayers p
SET tenant_id = pr.tenant_id::uuid
FROM public.profiles pr
WHERE p.tenant_id IS NULL
  AND pr.id = p.user_id
  AND pr.tenant_id IS NOT NULL;

UPDATE public.testimonies t
SET tenant_id = pr.tenant_id::uuid
FROM public.profiles pr
WHERE t.tenant_id IS NULL
  AND pr.id = t.user_id
  AND pr.tenant_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_prayers_tenant_id ON public.prayers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_testimonies_tenant_id ON public.testimonies(tenant_id);

-----------------------------------------------------------------------------
-- PRAYERS
-----------------------------------------------------------------------------

-- Drop every un-scoped SELECT/INSERT policy (Postgres ORs policies, so any
-- leftover USING (true) would keep the leak open).
DROP POLICY IF EXISTS "Anyone can view prayers" ON public.prayers;
DROP POLICY IF EXISTS "Anyone can read prayers" ON public.prayers;
DROP POLICY IF EXISTS "Authenticated users can view prayers" ON public.prayers;
DROP POLICY IF EXISTS "Authenticated users can submit prayers" ON public.prayers;
DROP POLICY IF EXISTS "Users can create prayers" ON public.prayers;

CREATE POLICY "Prayers select tenant scoped"
ON public.prayers FOR SELECT TO authenticated
USING (
  auth.uid() = user_id
  OR tenant_id IS NULL
  OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
  OR is_admin_or_employee()
);

CREATE POLICY "Prayers insert own tenant scoped"
ON public.prayers FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND (tenant_id IS NULL OR tenant_id::text = (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
);

-----------------------------------------------------------------------------
-- TESTIMONIES
-----------------------------------------------------------------------------

DROP POLICY IF EXISTS "Anyone can read testimonies" ON public.testimonies;
DROP POLICY IF EXISTS "Anyone can view testimonies" ON public.testimonies;
DROP POLICY IF EXISTS "Authenticated users can view testimonies" ON public.testimonies;
DROP POLICY IF EXISTS "Authenticated users can submit testimonies" ON public.testimonies;
DROP POLICY IF EXISTS "Users can create testimonies" ON public.testimonies;

CREATE POLICY "Testimonies select tenant scoped"
ON public.testimonies FOR SELECT TO authenticated
USING (
  auth.uid() = user_id
  OR tenant_id IS NULL
  OR tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
  OR is_admin_or_employee()
);

CREATE POLICY "Testimonies insert own tenant scoped"
ON public.testimonies FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND (tenant_id IS NULL OR tenant_id::text = (SELECT tenant_id FROM profiles WHERE id = auth.uid()))
);