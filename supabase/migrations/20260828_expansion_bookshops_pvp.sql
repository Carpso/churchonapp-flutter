-- ═══════════════════════════════════════════════════════════════
-- Expansion readiness + Bookshop roles + Cross-tenant PvP
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Bookshops: add owner + church + approval columns ─────────
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected'));
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS tenant_type TEXT CHECK (tenant_type IN ('independent','church_managed'));
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'ZMW';

-- ── 2. Rebuild RLS policies for bookshops ────────────────────────
DROP POLICY IF EXISTS "bookshops_select" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_insert" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_update" ON public.bookshops;
DROP POLICY IF EXISTS "bookshops_delete" ON public.bookshops;

-- Everyone can read approved bookshops
CREATE POLICY "bookshops_select" ON public.bookshops FOR SELECT USING (
  status = 'approved'
  OR auth.uid() = owner_id
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  OR (church_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.churches c WHERE c.id = church_id AND c.tenant_id IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
    )
  ))
);

-- Any authenticated user can create a bookshop (owner)
CREATE POLICY "bookshops_insert" ON public.bookshops FOR INSERT WITH CHECK (
  auth.uid() = owner_id
  AND status = 'pending'
);

-- Owner can update their own; superadmin/COA can approve; church admins can manage church bookshops
CREATE POLICY "bookshops_update" ON public.bookshops FOR UPDATE USING (
  auth.uid() = owner_id
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  OR (church_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.churches c WHERE c.id = church_id AND c.tenant_id IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
    )
  ))
);

-- Only superadmin can delete
CREATE POLICY "bookshops_delete" ON public.bookshops FOR DELETE USING (
  auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
);

-- ── 3. Add seed churches for Zimbabwe expansion ──────────────────
DO $$
DECLARE
  rec RECORD;
  new_id UUID;
BEGIN
  FOR rec IN (
    SELECT * FROM (VALUES
      ('zw_5', 'Celebration Church Hatfield', 'celebration-hatfield', 'Hatfield, Harare', -17.8700, 31.0500, '#8B5CF6'),
      ('zw_6', 'Faith World Ministries', 'faith-world', 'Borrowdale, Harare', -17.7500, 31.0800, '#10B981'),
      ('zw_7', 'Harare Baptist Church', 'harare-baptist', 'Avondale, Harare', -17.7900, 31.0300, '#3B82F6'),
      ('zw_8', 'Victory Family Church', 'victory-family', 'Msasa, Harare', -17.8400, 31.1000, '#F59E0B'),
      ('zw_9', 'Bulawayo Family Church', 'bulawayo-family', 'Khumalo, Bulawayo', -20.1600, 28.5700, '#EF4444'),
      ('zw_10', 'Gweru Christian Centre', 'gweru-cc', 'Gweru CBD', -19.4500, 29.8100, '#6366F1'),
      ('zw_11', 'Mutare Baptist', 'mutare-baptist', 'Mutare CBD', -18.9700, 32.6700, '#14B8A6'),
      ('zw_12', 'Masvingo Central Church', 'masvingo-central', 'Masvingo CBD', -20.0700, 30.8300, '#F97316')
    ) AS t(seed_ref, name, slug, address, lat, lng, color)
  ) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.churches WHERE slug = rec.slug) THEN
      new_id := gen_random_uuid();
      INSERT INTO public.churches (id, tenant_id, name, slug, address, latitude, longitude, primary_color, country, is_verified, subscription_ends_at)
      VALUES (new_id, new_id, rec.name, rec.slug, rec.address, rec.lat, rec.lng, rec.color, 'Zimbabwe', true, NOW() + INTERVAL '3650 days');
      INSERT INTO public.tenants (id, name, type, created_at)
      VALUES (new_id, rec.name, 'church', NOW());
    END IF;
  END LOOP;
END $$;

-- ── 4. Add more Zambia expansion churches ────────────────────────
DO $$
DECLARE
  rec RECORD;
  new_id UUID;
BEGIN
  FOR rec IN (
    SELECT * FROM (VALUES
      ('zm_37', 'Kabwe Word Church', 'kabwe-word', 'Kabwe CBD', -14.4400, 28.4500, '#8B5CF6'),
      ('zm_38', 'Kafue Community Church', 'kafue-cc', 'Kafue Town', -15.7700, 28.1800, '#10B981'),
      ('zm_39', 'Choma Christian Centre', 'choma-cc', 'Choma, Southern Province', -16.8100, 26.9800, '#3B82F6'),
      ('zm_40', 'Mongu Evangelical Church', 'mongu-evangelical', 'Mongu, Western Province', -15.2700, 23.1300, '#F59E0B'),
      ('zm_41', 'Kasama Baptist Church', 'kasama-baptist', 'Kasama, Northern Province', -10.2100, 31.1800, '#EF4444'),
      ('zm_42', 'Chipata Central Church', 'chipata-central', 'Chipata, Eastern Province', -13.6400, 32.6400, '#6366F1'),
      ('zm_43', 'Solwezi Christian Fellowship', 'solwezi-fellowship', 'Solwezi, North-Western', -12.1800, 26.3900, '#14B8A6'),
      ('zm_44', 'Mansa United Church', 'mansa-united', 'Mansa, Luapula Province', -11.2000, 28.8900, '#F97316'),
      ('zm_45', 'Livingstone Christian Assembly', 'livingstone-assembly', 'Livingstone, Southern Province', -17.8500, 25.8600, '#DC2626')
    ) AS t(seed_ref, name, slug, address, lat, lng, color)
  ) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.churches WHERE slug = rec.slug) THEN
      new_id := gen_random_uuid();
      INSERT INTO public.churches (id, tenant_id, name, slug, address, latitude, longitude, primary_color, country, is_verified, subscription_ends_at)
      VALUES (new_id, new_id, rec.name, rec.slug, rec.address, rec.lat, rec.lng, rec.color, 'Zambia', true, NOW() + INTERVAL '3650 days');
      INSERT INTO public.tenants (id, name, type, created_at)
      VALUES (new_id, rec.name, 'church', NOW());
    END IF;
  END LOOP;
END $$;

-- ── 5. Add tenant_id to pvp_matches for cross-tenant matching ────
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS cross_tenant BOOLEAN DEFAULT false;

-- ── 6. Verify ───────────────────────────────────────────────────
SELECT 'churches_zm' AS region, COUNT(*) FROM public.churches WHERE id::text LIKE 'zm_%'
UNION ALL
SELECT 'churches_zw', COUNT(*) FROM public.churches WHERE id::text LIKE 'zw_%'
UNION ALL
SELECT 'bookshops_columns_ok', COUNT(*) FROM information_schema.columns WHERE table_name='bookshops' AND column_name IN ('owner_id','status','church_id','tenant_type');
