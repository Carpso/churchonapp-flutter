-- ============================================================
-- Game Settings table for per-tenant game enable/disable
-- + stock column for marketplace_items
-- ============================================================

-- 1. Game Settings
CREATE TABLE IF NOT EXISTS public.game_settings (
    tenant_id TEXT NOT NULL,
    game_id TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (tenant_id, game_id)
);

ALTER TABLE public.game_settings ENABLE ROW LEVEL SECURITY;

-- Only authenticated users from the same tenant can read
DROP POLICY IF EXISTS "Tenant members can read game settings" ON public.game_settings;
CREATE POLICY "Tenant members can read game settings" ON public.game_settings
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND tenant_id = game_settings.tenant_id
        )
    );

-- Superadmins and employees can insert/update/delete
DROP POLICY IF EXISTS "Superadmins and employees can manage game settings" ON public.game_settings;
CREATE POLICY "Superadmins and employees can manage game settings" ON public.game_settings
    FOR ALL TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND (role = 'superadmin' OR role = 'employee')
        )
    );

-- 2. Add stock column to marketplace_items
ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS stock INTEGER DEFAULT 0;

-- 3. Add tenant_id to marketplace_items for church-scoped bookshops
ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS tenant_id TEXT;
CREATE INDEX IF NOT EXISTS idx_marketplace_items_tenant ON public.marketplace_items(tenant_id);

