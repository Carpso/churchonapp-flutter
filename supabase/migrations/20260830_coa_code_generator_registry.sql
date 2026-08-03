-- ═══════════════════════════════════════════════════════════════
-- COA Code Generator: registry table + missing sequences + wallet_id
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add missing sequences to id_sequences ────────────────────
INSERT INTO public.id_sequences (name, value) VALUES
  ('membership_id', 0)
ON CONFLICT (name) DO NOTHING;

-- ── 2. Generated codes registry table ──────────────────────────
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

-- ── 3. Add wallet_id and membership_id to profiles ─────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS wallet_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS membership_id TEXT;

-- ── 4. RLS ─────────────────────────────────────────────────────
ALTER TABLE public.generated_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "generated_codes_select_own" ON "public".generated_codes;
CREATE POLICY "generated_codes_select_own" ON "public".generated_codes
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "generated_codes_insert_own" ON "public".generated_codes;
CREATE POLICY "generated_codes_insert_own" ON "public".generated_codes
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

DROP POLICY IF EXISTS "generated_codes_admin_all" ON "public".generated_codes;
CREATE POLICY "generated_codes_admin_all" ON "public".generated_codes
  FOR ALL USING (
    auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
    OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  );

-- ── 5. Verify ──────────────────────────────────────────────────
SELECT 'generated_codes_created' AS check, COUNT(*) FROM public.generated_codes;
SELECT 'id_sequences_total' AS check, COUNT(*) FROM public.id_sequences;
