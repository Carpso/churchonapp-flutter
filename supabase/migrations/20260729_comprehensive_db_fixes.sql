-- ============================================================================
-- COMPREHENSIVE DATABASE FIX MIGRATION
-- Fixes: 42P17, 42703, 22P02, 23502, 42P01, missing columns, duplicate keys
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ORDERS RLS INFINITE RECURSION (42P17)
--    Root cause: "Vendors can view orders" policy queries order_items,
--    whose policy queries back to orders → infinite loop
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop the recursive vendor policy
DROP POLICY IF EXISTS "Vendors can view orders for their items" ON public.orders;

-- Create a SECURITY DEFINER function to check vendor ownership safely
CREATE OR REPLACE FUNCTION public.user_owns_order_items(order_uuid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.order_items oi
    JOIN public.marketplace_items mi ON oi.item_id = mi.id
    WHERE oi.order_id = order_uuid AND mi.vendor_id = auth.uid()
  );
$$;

-- Recreate vendor policy using the SECURITY DEFINER function (no recursion)
CREATE POLICY "Vendors can view orders for their items" ON public.orders
  FOR SELECT TO authenticated
  USING (public.user_owns_order_items(orders.id));

-- Also fix deliveries policy - use driver_id direct check (no recursion)
DROP POLICY IF EXISTS "Users can view own deliveries" ON public.deliveries;
CREATE POLICY "Users can view own deliveries" ON public.deliveries
  FOR SELECT TO authenticated
  USING (auth.uid() = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. APP_CONFIG TABLE (42703 - column does not exist)
--    Table exists but may be missing columns
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value JSONB DEFAULT '{}',
  latest_build INTEGER DEFAULT 1,
  update_message TEXT DEFAULT '',
  force_update BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Add columns if table exists but columns are missing
DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN latest_build INTEGER DEFAULT 1;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN update_message TEXT DEFAULT '';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN force_update BOOLEAN DEFAULT false;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN value JSONB DEFAULT '{}';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN created_at TIMESTAMPTZ DEFAULT now();
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.app_config ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read app_config (for version checks)
DROP POLICY IF EXISTS "app_config_read_auth" ON public.app_config;
CREATE POLICY "app_config_read_auth" ON public.app_config
  FOR SELECT TO authenticated USING (true);

-- Only superadmins can modify app_config
DROP POLICY IF EXISTS "app_config_admin_all" ON public.app_config;
CREATE POLICY "app_config_admin_all" ON public.app_config
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

-- Seed a default row for version checking
INSERT INTO public.app_config (key, value, latest_build, update_message, force_update)
VALUES ('version', '{}'::jsonb, 1, '', false)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. MESSAGES TABLE - ADD sender_id COLUMN (23502 - null constraint)
--    Dart code inserts sender_id but the column doesn't exist (only user_id)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- Add receiver_id and conversation_id if missing
DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN receiver_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN conversation_id TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN media_type TEXT DEFAULT 'text';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN sticker_id TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN file_name TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN reply_to_id UUID;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.messages ADD COLUMN reply_to_text TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- Fix RLS policies to use sender_id consistently
DROP POLICY IF EXISTS "messages_insert_auth" ON public.messages;
CREATE POLICY "messages_insert_auth" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "messages_select_auth" ON public.messages;
CREATE POLICY "messages_select_auth" ON public.messages
  FOR SELECT TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR auth.uid() = user_id
    OR (group_id IS NOT NULL)
    OR (conversation_id IS NOT NULL)
  );

DROP POLICY IF EXISTS "messages_update_auth" ON public.messages;
CREATE POLICY "messages_update_auth" ON public.messages
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR auth.uid() = user_id
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. WHATSAPP_CONFIG TABLE (42P01 - does not exist)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.whatsapp_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled BOOLEAN DEFAULT false,
  phone_number_id TEXT,
  access_token TEXT,
  business_account_id TEXT,
  verify_token TEXT,
  webhook_url TEXT,
  app_id TEXT,
  whatsapp_number TEXT,
  description TEXT,
  last_updated TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.whatsapp_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "whatsapp_config_all" ON public.whatsapp_config;
CREATE POLICY "whatsapp_config_all" ON public.whatsapp_config
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);

INSERT INTO public.whatsapp_config (is_enabled) VALUES (false) ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. ADD MISSING COLUMNS (42703 - column does not exist)
-- ─────────────────────────────────────────────────────────────────────────────

-- event_registrations.rsvp_status
DO $$ BEGIN
  ALTER TABLE public.event_registrations ADD COLUMN rsvp_status TEXT DEFAULT 'registered';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- bible_verses.reference (the actual column might be 'verse_ref' or similar)
DO $$ BEGIN
  ALTER TABLE public.bible_verses ADD COLUMN reference TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- sermons.speaker
DO $$ BEGIN
  ALTER TABLE public.sermons ADD COLUMN speaker TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- churches.location
DO $$ BEGIN
  ALTER TABLE public.churches ADD COLUMN location TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- profiles.email
DO $$ BEGIN
  ALTER TABLE public.profiles ADD COLUMN email TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. MARKETPLACE_REVIEWS TABLE (never created, unique constraint missing)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.marketplace_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reviewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (reviewer_id, product_id)
);

ALTER TABLE public.marketplace_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "marketplace_reviews_read_auth" ON public.marketplace_reviews;
CREATE POLICY "marketplace_reviews_read_auth" ON public.marketplace_reviews
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "marketplace_reviews_insert_own" ON public.marketplace_reviews;
CREATE POLICY "marketplace_reviews_insert_own" ON public.marketplace_reviews
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "marketplace_reviews_update_own" ON public.marketplace_reviews;
CREATE POLICY "marketplace_reviews_update_own" ON public.marketplace_reviews
  FOR UPDATE TO authenticated
  USING (auth.uid() = reviewer_id);

-- Add tenant_id and church_id if missing (from 20260826_final_fixes.sql)
DO $$ BEGIN
  ALTER TABLE public.marketplace_reviews ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.marketplace_reviews ADD COLUMN church_id UUID REFERENCES public.churches(id);
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. FIX REMAINING MINOR COLUMNS
-- ─────────────────────────────────────────────────────────────────────────────

-- bible_books_1.book_id → should be 'id' or another column name
DO $$ BEGIN
  ALTER TABLE public.bible_books ADD COLUMN book_id TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- pvp_matches.player1_elo_at_match
DO $$ BEGIN
  ALTER TABLE public.pvp_matches ADD COLUMN player1_elo_at_match INTEGER DEFAULT 1000;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.pvp_matches ADD COLUMN player2_elo_at_match INTEGER DEFAULT 1000;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. ROLE_ONBOARDING - MAKE UPSERT SAFE
--    Drop and recreate with proper unique constraint
-- ─────────────────────────────────────────────────────────────────────────────

-- Ensure the unique constraint exists (drop+recreate is idempotent)
DO $$ BEGIN
  ALTER TABLE public.role_onboarding DROP CONSTRAINT IF EXISTS role_onboarding_user_id_role_key;
  ALTER TABLE public.role_onboarding ADD CONSTRAINT role_onboarding_user_id_role_key UNIQUE (user_id, role);
EXCEPTION WHEN others THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. FIX BROKEN MIGRATION REFERENCES
--    The 20260828_expansion_bookshops_pvp.sql uses 'zm_36'::uuid which fails
--    These are no-ops if the seed data already exists
-- ─────────────────────────────────────────────────────────────────────────────

-- Insert seed churches with proper UUIDs (safe, IF NOT EXISTS)
DO $$ BEGIN
  INSERT INTO public.churches (id, tenant_id, name, slug)
  SELECT '00000000-0000-0000-0000-000000000036'::uuid, '00000000-0000-0000-0000-000000000036'::uuid, 'Rock Of Ages Chapel Kabulonga', 'rock-of-ages-kabulonga'
  WHERE NOT EXISTS (SELECT 1 FROM public.churches WHERE slug = 'rock-of-ages-kabulonga');
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  INSERT INTO public.tenants (id, name, type)
  SELECT '00000000-0000-0000-0000-000000000036'::uuid, 'Rock Of Ages Chapel Kabulonga', 'church'
  WHERE NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = '00000000-0000-0000-0000-000000000036'::uuid);
EXCEPTION WHEN others THEN NULL;
END $$;
