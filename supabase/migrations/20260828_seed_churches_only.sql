-- Seed Zimbabwe expansion churches with proper UUIDs
-- The seed_ref column stores the app-level identifier (e.g. 'zw_5')
-- slug is used for app-level fallback lookups
DO $$
DECLARE
  rec RECORD;
  new_id uuid;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('zw_5'::text, 'celebration-hatfield', 'Celebration Church Hatfield', 'Hatfield, Harare', -17.8700, 31.0500, '#8B5CF6'),
    ('zw_6', 'faith-world', 'Faith World Ministries', 'Borrowdale, Harare', -17.7500, 31.0800, '#10B981'),
    ('zw_7', 'harare-baptist', 'Harare Baptist Church', 'Avondale, Harare', -17.7900, 31.0300, '#3B82F6'),
    ('zw_8', 'victory-family', 'Victory Family Church', 'Msasa, Harare', -17.8400, 31.1000, '#F59E0B'),
    ('zw_9', 'bulawayo-family', 'Bulawayo Family Church', 'Khumalo, Bulawayo', -20.1600, 28.5700, '#EF4444'),
    ('zw_10', 'gweru-cc', 'Gweru Christian Centre', 'Gweru CBD', -19.4500, 29.8100, '#6366F1'),
    ('zw_11', 'mutare-baptist', 'Mutare Baptist', 'Mutare CBD', -18.9700, 32.6700, '#14B8A6'),
    ('zw_12', 'masvingo-central', 'Masvingo Central Church', 'Masvingo CBD', -20.0700, 30.8300, '#F97316')
  ) AS t(ref, slug, name, address, lat, lng, color) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.churches WHERE slug = rec.slug) THEN
      new_id := gen_random_uuid();
      -- Insert tenant first (churches.tenant_id references tenants.id)
      INSERT INTO public.tenants (id, name, type) VALUES (new_id, rec.name, 'church')
      ON CONFLICT (id) DO NOTHING;
      -- Then insert church with tenant_id referencing the tenant we just created
      INSERT INTO public.churches (id, tenant_id, name, slug, address, latitude, longitude, primary_color, country, is_verified, subscription_ends_at)
      VALUES (new_id, new_id, rec.name, rec.slug, rec.address, rec.lat, rec.lng, rec.color, 'Zimbabwe', true, NOW() + INTERVAL '3650 days');
    END IF;
  END LOOP;
END $$;

-- Seed Zambia expansion churches
DO $$
DECLARE
  rec RECORD;
  new_id uuid;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('zm_37', 'kabwe-word', 'Kabwe Word Church', 'Kabwe CBD', -14.4400, 28.4500, '#8B5CF6'),
    ('zm_38', 'kafue-cc', 'Kafue Community Church', 'Kafue Town', -15.7700, 28.1800, '#10B981'),
    ('zm_39', 'choma-cc', 'Choma Christian Centre', 'Choma, Southern Province', -16.8100, 26.9800, '#3B82F6'),
    ('zm_40', 'mongu-evangelical', 'Mongu Evangelical Church', 'Mongu, Western Province', -15.2700, 23.1300, '#F59E0B'),
    ('zm_41', 'kasama-baptist', 'Kasama Baptist Church', 'Kasama, Northern Province', -10.2100, 31.1800, '#EF4444'),
    ('zm_42', 'chipata-central', 'Chipata Central Church', 'Chipata, Eastern Province', -13.6400, 32.6400, '#6366F1'),
    ('zm_43', 'solwezi-fellowship', 'Solwezi Christian Fellowship', 'Solwezi, North-Western', -12.1800, 26.3900, '#14B8A6'),
    ('zm_44', 'mansa-united', 'Mansa United Church', 'Mansa, Luapula Province', -11.2000, 28.8900, '#F97316'),
    ('zm_45', 'livingstone-assembly', 'Livingstone Christian Assembly', 'Livingstone, Southern Province', -17.8500, 25.8600, '#DC2626')
  ) AS t(ref, slug, name, address, lat, lng, color) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.churches WHERE slug = rec.slug) THEN
      new_id := gen_random_uuid();
      INSERT INTO public.tenants (id, name, type) VALUES (new_id, rec.name, 'church')
      ON CONFLICT (id) DO NOTHING;
      INSERT INTO public.churches (id, tenant_id, name, slug, address, latitude, longitude, primary_color, country, is_verified, subscription_ends_at)
      VALUES (new_id, new_id, rec.name, rec.slug, rec.address, rec.lat, rec.lng, rec.color, 'Zambia', true, NOW() + INTERVAL '3650 days');
    END IF;
  END LOOP;
END $$;

-- Add tenant_id and cross_tenant columns to pvp_matches
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS cross_tenant BOOLEAN DEFAULT false;

SELECT 'zm_churches' AS region, COUNT(*) FROM public.churches WHERE country = 'Zambia'
UNION ALL
SELECT 'zw_churches', COUNT(*) FROM public.churches WHERE country = 'Zimbabwe';
