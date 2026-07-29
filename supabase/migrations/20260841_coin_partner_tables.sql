-- ═══════════════════════════════════════════════════════════════
-- CHURCH ON APP - MISSING COIN & PARTNER TABLES
-- Creates coin_purchases, coin_redemptions, partner_tenants, partner_offers
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. COIN PURCHASES TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coin_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  coins_amount INT NOT NULL,
  price_kwacha INT NOT NULL,
  payment_ref TEXT,
  payment_method TEXT,
  package_label TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.coin_purchases ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "coin_purchases_select_own" ON public.coin_purchases
    FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coin_purchases_insert_own" ON public.coin_purchases
    FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coin_purchases_admin_all" ON public.coin_purchases
    FOR ALL USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_coin_purchases_user ON public.coin_purchases(user_id);

-- ── 2. COIN REDEMPTIONS TABLE ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coin_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  amount INT NOT NULL,
  redemption_type TEXT NOT NULL,
  partner_id TEXT,
  description TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.coin_redemptions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "coin_redemptions_select_own" ON public.coin_redemptions
    FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coin_redemptions_insert_own" ON public.coin_redemptions
    FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coin_redemptions_admin_all" ON public.coin_redemptions
    FOR ALL USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_coin_redemptions_user ON public.coin_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_coin_redemptions_type ON public.coin_redemptions(redemption_type);

-- ── 3. PARTNER TENANTS TABLE ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.partner_tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('bookshop', 'coffee_shop', 'restaurant', 'other')),
  description TEXT,
  location TEXT,
  logo_url TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.partner_tenants ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_select" ON public.partner_tenants
    FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_insert" ON public.partner_tenants
    FOR INSERT WITH CHECK (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_update" ON public.partner_tenants
    FOR UPDATE USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_delete" ON public.partner_tenants
    FOR DELETE USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 4. PARTNER OFFERS TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.partner_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id UUID REFERENCES partner_tenants(id),
  title TEXT NOT NULL,
  description TEXT,
  coins_required INT NOT NULL,
  image_url TEXT,
  is_active BOOLEAN DEFAULT true,
  redeemed_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.partner_offers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "partner_offers_select" ON public.partner_offers
    FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_offers_insert" ON public.partner_offers
    FOR INSERT WITH CHECK (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_offers_update" ON public.partner_offers
    FOR UPDATE USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 5. INCREMENT REDEEMED COUNTS RPC ─────────────────────────────
CREATE OR REPLACE FUNCTION increment_redeemed_count(offer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE partner_offers SET redeemed_count = redeemed_count + 1 WHERE id = offer_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION increment_redeemed_count FROM anon, authenticated;

COMMIT;