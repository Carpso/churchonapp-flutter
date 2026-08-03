-- ═══════════════════════════════════════════════════════════════
-- COMPREHENSIVE PRODUCTION FIX MIGRATION
-- Fixes all remaining issues from the 30-failing-migration audit:
-- 1. Ensures all critical tables exist (idempotent)
-- 2. Fixes type mismatches (tenant_id text→UUID casts)
-- 3. Adds missing RLS policies
-- 4. Ensures all SECURITY DEFINER functions have search_path
-- 5. Creates missing indexes for performance
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- SECTION 1: ENSURE CRITICAL TABLES EXIST
-- ──────────────────────────────────────────────────────────────

-- 1.1 id_sequences (code counter)
CREATE TABLE IF NOT EXISTS public.id_sequences (
  name TEXT PRIMARY KEY,
  value BIGINT NOT NULL DEFAULT 0
);

INSERT INTO public.id_sequences (name, value) VALUES
  ('tenant_code', 0),
  ('church_code', 0),
  ('bookshop_code', 0),
  ('tithe_card', 0),
  ('church_slug', 0),
  ('user_code', 0),
  ('referral_code', 0),
  ('wallet_id', 0),
  ('membership_id', 0),
  ('event_ticket', 0),
  ('payment_ref', 0)
ON CONFLICT (name) DO NOTHING;

-- 1.2 generated_codes (code registry)
CREATE TABLE IF NOT EXISTS public.generated_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code_type TEXT NOT NULL,
  code_value TEXT NOT NULL UNIQUE,
  country_iso TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_generated_codes_value ON public.generated_codes(code_value);
CREATE INDEX IF NOT EXISTS idx_generated_codes_user ON public.generated_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_generated_codes_type ON public.generated_codes(code_type);

-- RLS for generated_codes
ALTER TABLE public.generated_codes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "generated_codes_select_own" ON public.generated_codes
    FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "generated_codes_insert_own" ON public.generated_codes
    FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "generated_codes_admin_all" ON public.generated_codes
    FOR ALL USING (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 1.3 coin_purchases
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
    FOR ALL USING (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_coin_purchases_user ON public.coin_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_coin_purchases_ref ON public.coin_purchases(payment_ref);

-- 1.4 coin_redemptions
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
    FOR ALL USING (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_coin_redemptions_user ON public.coin_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_coin_redemptions_type ON public.coin_redemptions(redemption_type);

-- 1.5 partner_tenants
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
    FOR INSERT WITH CHECK (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_update" ON public.partner_tenants
    FOR UPDATE USING (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_tenants_delete" ON public.partner_tenants
    FOR DELETE USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'superadmin')
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 1.6 partner_offers
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
    FOR INSERT WITH CHECK (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "partner_offers_update" ON public.partner_offers
    FOR UPDATE USING (public.is_admin_or_employee());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ──────────────────────────────────────────────────────────────
-- SECTION 2: ENSURE ALL SECURITY DEFINER FUNCTIONS HAVE search_path
-- ──────────────────────────────────────────────────────────────

-- 2.1 increment_redeemed_count
CREATE OR REPLACE FUNCTION public.increment_redeemed_count(offer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE partner_offers SET redeemed_count = redeemed_count + 1 WHERE id = offer_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.increment_redeemed_count FROM anon, authenticated;

-- 2.2 next_id_sequence
CREATE OR REPLACE FUNCTION public.next_id_sequence(seq_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_val BIGINT;
BEGIN
  INSERT INTO public.id_sequences (name, value)
  VALUES (seq_name, 1)
  ON CONFLICT (name) DO UPDATE SET value = public.id_sequences.value + 1
  RETURNING value INTO next_val;
  RETURN LPAD(next_val::TEXT, 4, '0');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.next_id_sequence FROM anon;

-- 2.3 add_coins (ensure exists)
DROP FUNCTION IF EXISTS public.add_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.add_coins(p_user_id UUID, p_amount INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles SET coins = COALESCE(coins, 0) + p_amount WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_coins FROM anon;

-- ──────────────────────────────────────────────────────────────
-- SECTION 3: FIX TYPE MISMATCHES IN LATER MIGRATIONS
-- ──────────────────────────────────────────────────────────────

-- 3.1 Fix 20260849_backfill_role_from_assignments — tenant_id may be UUID after 20260837
-- The backfill compares ra.tenant_id = p.tenant_id. After 20260837, p.tenant_id is UUID.
-- If role_assignments.tenant_id is text, cast it.
-- (Triggers disabled: system backfill, not a user-initiated role change)
ALTER TABLE public.profiles DISABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles DISABLE TRIGGER trg_log_role_change;

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'role_assignments'
    AND column_name = 'tenant_id' AND data_type IN ('text', 'character varying')
  ) THEN
    -- Backfill with explicit cast
    UPDATE profiles p
    SET role = ra.role_name
    FROM role_assignments ra
    WHERE ra.user_id = p.id
      AND ra.tenant_id::uuid = p.tenant_id
      AND ra.status = 'approved'
      AND p.role != ra.role_name;

    UPDATE profiles p
    SET role = 'member'
    WHERE NOT EXISTS (
      SELECT 1 FROM role_assignments ra
      WHERE ra.user_id = p.id
        AND ra.tenant_id::uuid = p.tenant_id
        AND ra.status = 'approved'
    )
    AND p.role != 'member'
    AND p.tenant_id IS NOT NULL;
  ELSE
    -- tenant_id is already UUID type
    UPDATE profiles p
    SET role = ra.role_name
    FROM role_assignments ra
    WHERE ra.user_id = p.id
      AND ra.tenant_id::text = p.tenant_id
      AND ra.status = 'approved'
      AND p.role != ra.role_name;

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
  END IF;
END $$;

ALTER TABLE public.profiles ENABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles ENABLE TRIGGER trg_log_role_change;

-- ──────────────────────────────────────────────────────────────
-- SECTION 4: ADD MISSING PERFORMANCE INDEXES
-- ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_profiles_tenant_id ON public.profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_churches_tenant_id ON public.churches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_user ON public.role_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_tenant ON public.role_assignments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_coa_payments_status ON public.coa_payments(status);
CREATE INDEX IF NOT EXISTS idx_transactions_user ON public.transactions(user_id);

-- ──────────────────────────────────────────────────────────────
-- SECTION 5: ENSURE ALL TABLES HAVE RLS ENABLED
-- ──────────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.live_streams ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.prayers ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.testimonies ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.marketplace_items ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.sermons ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.coa_payments ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ──────────────────────────────────────────────────────────────
-- SECTION 6: ADD wallet_id AND membership_id TO profiles IF MISSING
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS wallet_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS membership_id TEXT;

COMMIT;
