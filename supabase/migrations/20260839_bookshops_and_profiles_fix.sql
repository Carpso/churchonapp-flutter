-- ═══════════════════════════════════════════════════════════════
-- CHURCH ON APP - BOOKSHOPS TABLE & PROFILES TENANT_ID FIX
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Create bookshops table ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bookshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id),
  name TEXT NOT NULL,
  description TEXT,
  contact TEXT,
  location TEXT,
  logo_url TEXT,
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bookshops ENABLE ROW LEVEL SECURITY;

-- RLS: Anyone can view active bookshops; owners and superadmins can manage
DO $$ BEGIN
  CREATE POLICY "bookshops_select" ON public.bookshops FOR SELECT USING (
    is_active = true OR 
    auth.uid() = owner_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "bookshops_insert" ON public.bookshops FOR INSERT WITH CHECK (
    auth.uid() = owner_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "bookshops_update" ON public.bookshops FOR UPDATE USING (
    auth.uid() = owner_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "bookshops_delete" ON public.bookshops FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'super_admin'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2. Add country column to tenants table ─────────────────────
ALTER TABLE IF EXISTS public.tenants ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'Zambia';

-- ── 3. Fix profiles.tenant_id: Add UUID column and migrate data ──
-- Step 1: Add a new UUID column
ALTER TABLE IF EXISTS public.profiles ADD COLUMN IF NOT EXISTS tenant_uuid UUID REFERENCES public.tenants(id);

-- Step 2: Migrate existing text tenant_id values to UUID
-- Only migrate values that are valid UUIDs
UPDATE public.profiles 
SET tenant_uuid = tenant_id::uuid 
WHERE tenant_id IS NOT NULL 
  AND tenant_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Step 3: For profiles with text tenant_id that aren't valid UUIDs, try to find the tenant by slug
-- This handles legacy data where tenant_id might be a church slug
UPDATE public.profiles p
SET tenant_uuid = c.tenant_id
FROM public.churches c
WHERE p.tenant_id IS NOT NULL 
  AND p.tenant_uuid IS NULL
  AND c.slug = p.tenant_id;

-- Step 4: Create index on the new column
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_uuid ON public.profiles(tenant_uuid);

-- ── 4. Add tenant_id to register_church_screen's churches insert ──
-- Note: This is handled in the Flutter code, but we add a trigger
-- to auto-create tenants row if one doesn't exist for a church insert
CREATE OR REPLACE FUNCTION public.ensure_tenant_on_church_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- If no tenant_id provided, create one
  IF NEW.tenant_id IS NULL THEN
    INSERT INTO public.tenants (id, name, type, country)
    VALUES (NEW.id, NEW.name, 'church', COALESCE(NEW.country, 'Zambia'))
    ON CONFLICT (id) DO NOTHING;
    NEW.tenant_id := NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_tenant_on_church_insert ON public.churches;
CREATE TRIGGER trg_ensure_tenant_on_church_insert
  BEFORE INSERT ON public.churches
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_tenant_on_church_insert();

-- ── 5. Add tenant code generation support ──────────────────────
-- Add tenant_code column to tenants table
ALTER TABLE IF EXISTS public.tenants ADD COLUMN IF NOT EXISTS tenant_code TEXT UNIQUE;

-- Function to generate tenant code
CREATE OR REPLACE FUNCTION public.generate_tenant_code(p_country TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_iso TEXT;
  v_seq TEXT;
  v_code TEXT;
BEGIN
  v_iso := CASE 
    WHEN p_country ILIKE '%zambia%' THEN 'ZM'
    WHEN p_country ILIKE '%zimbabwe%' THEN 'ZW'
    WHEN p_country ILIKE '%kenya%' THEN 'KE'
    ELSE 'ZM'
  END;
  
  v_seq := public.next_id_sequence('tenant_code');
  v_code := 'COA-' || v_iso || '_T_' || v_seq;
  
  RETURN v_code;
END;
$$;

COMMIT;