-- ════════════════════════════════════════════════════════════════
-- Year Planner: adds user-level planning + RPC for attendee count
-- ════════════════════════════════════════════════════════════════

-- 1. RPC: atomically increment attendee_count
CREATE OR REPLACE FUNCTION public.increment_attendee_count(event_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE events SET attendee_count = COALESCE(attendee_count, 0) + 1 WHERE id = event_id;
END;
$$;

-- 2. Add user_id column to year_planner (for personal user programs)
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- 3. Add metadata columns for richer planner
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS color TEXT DEFAULT '#FFD700';
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'general';
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN DEFAULT false;
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS recurring_pattern TEXT; -- weekly, monthly, yearly, etc.
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS end_date DATE;
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS location TEXT;
ALTER TABLE year_planner ADD COLUMN IF NOT EXISTS link_url TEXT;

-- 4. RLS for planner items (drop first to allow re-run)
ALTER TABLE year_planner ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own planner items" ON year_planner;
CREATE POLICY "Users can manage own planner items"
  ON year_planner FOR ALL
  TO authenticated
  USING (auth.uid()::text = user_id::text OR user_id IS NULL)
  WITH CHECK (auth.uid()::text = user_id::text);

DROP POLICY IF EXISTS "Tenants can manage tenant planner items" ON year_planner;
CREATE POLICY "Tenants can manage tenant planner items"
  ON year_planner FOR ALL
  TO authenticated
  USING (
    tenant_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id::text = auth.uid()::text
      AND tenant_id::text = year_planner.tenant_id::text
      AND role IN ('admin', 'superadmin', 'employee', 'pastor')
    )
  );
