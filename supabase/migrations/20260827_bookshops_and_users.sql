-- ═══════════════════════════════════════════════════════════════
-- Bookshops, Superadmin tenant access, User visibility
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add DELETE policy for superadmins on tenants ──────────────
DROP POLICY IF EXISTS "tenants_delete" ON public.tenants;
CREATE POLICY "tenants_delete" ON public.tenants FOR DELETE USING (
  auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
);

-- ── 2. Bookshops table (tenant type = 'bookshop') ────────────────
CREATE TABLE IF NOT EXISTS public.bookshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  owner_name TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  country TEXT DEFAULT 'Zambia',
  logo_url TEXT,
  is_verified BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bookshops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bookshops_select" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_insert" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_update" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_delete" ON public.bookshops;

CREATE POLICY "bookshops_select" ON public.bookshops FOR SELECT USING (true);
CREATE POLICY "bookshops_insert" ON public.bookshops FOR INSERT WITH CHECK (
  auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
);
CREATE POLICY "bookshops_update" ON public.bookshops FOR UPDATE USING (
  auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
);
CREATE POLICY "bookshops_delete" ON public.bookshops FOR DELETE USING (
  auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
);

-- ── 3. Ensure all profiles have tenant_id populated ──────────────
-- Some profiles might have NULL tenant_id; copy from their church association
UPDATE public.profiles p
SET tenant_id = c.tenant_id
FROM public.churches c
WHERE p.tenant_id IS NULL
  AND c.id = p.church_id;

-- If still NULL (no church linked), keep NULL (user is not tenant-scoped)

-- ── 4. Verify ───────────────────────────────────────────────────
SELECT 'tenants' AS entity, type, COUNT(*) FROM public.tenants GROUP BY type
UNION ALL
SELECT 'bookshops', 'bookshop', COUNT(*) FROM public.bookshops
UNION ALL
SELECT 'profiles_with_tenant', 'profile', COUNT(*) FROM public.profiles WHERE tenant_id IS NOT NULL;
