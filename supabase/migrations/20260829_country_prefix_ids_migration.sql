-- ═══════════════════════════════════════════════════════════════
-- Country-prefix ID system + bookshop independence + quiz expansion
-- ═══════════════════════════════════════════════════════════════

-- ── 1. ID sequences table for CodeGeneratorService ───────────────
CREATE TABLE IF NOT EXISTS public.id_sequences (
  name TEXT PRIMARY KEY,
  value BIGINT NOT NULL DEFAULT 0
);

-- Seed initial sequence values
INSERT INTO public.id_sequences (name, value) VALUES
  ('tenant_code', 0),
  ('church_code', 0),
  ('bookshop_code', 0),
  ('tithe_card', 0),
  ('church_slug', 0)
ON CONFLICT (name) DO NOTHING;

-- RPC to atomically increment and return next value
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

-- ── 2. Make church_id nullable on bookshops (standalone bookshop support) ──
ALTER TABLE IF EXISTS public.bookshops ALTER COLUMN church_id DROP NOT NULL;
ALTER TABLE IF EXISTS public.bookshops ALTER COLUMN church_id DROP DEFAULT;

-- ── 3. Add more columns for standalone bookshop tenants ──────────────────
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS primary_color TEXT DEFAULT '#8B5CF6';

-- Add unique constraint for bookshop slug (nullable)
DROP INDEX IF EXISTS idx_bookshops_slug;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bookshops_slug ON public.bookshops(slug) WHERE slug IS NOT NULL;

-- ── 4. Add an 'other' option for country in churches ─────────────────────
ALTER TABLE IF EXISTS public.churches ALTER COLUMN country SET DEFAULT 'Other';

-- ── 5. RLS for bookshops – update to also allow standalone owners ────────
-- profiles.tenant_id is TEXT type (known issue), cast churches.tenant_id to match
DROP POLICY IF EXISTS "bookshops_update" ON public.bookshops;
CREATE POLICY "bookshops_update" ON public.bookshops FOR UPDATE USING (
  auth.uid() = owner_id
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
  OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  OR (church_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.churches c WHERE c.id = church_id AND c.tenant_id::text IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
    )
  ))
  OR (church_id IS NULL AND owner_id = auth.uid())
);

-- ── 6. Verify ──────────────────────────────────────────────────
SELECT 'id_sequences_created' AS check, COUNT(*) FROM public.id_sequences;
