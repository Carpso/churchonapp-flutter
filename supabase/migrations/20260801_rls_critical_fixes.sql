-- ============================================================
-- Migration: 20260801_rls_critical_fixes
-- Drop and recreate RLS policies that had WITH CHECK (true)
-- or USING (true) on critical tables.
-- Safe to re-run: each table wrapped in its own exception block.
-- ============================================================

-- ── platform_settings ──────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view platform settings" ON platform_settings;
  DROP POLICY IF EXISTS "Authenticated users can view platform settings" ON platform_settings;
  DROP POLICY IF EXISTS "Platform settings all access" ON platform_settings;
  DROP POLICY IF EXISTS "Only admins can modify platform settings" ON platform_settings;
  CREATE POLICY "Authenticated users can view platform settings" ON platform_settings
    FOR SELECT TO authenticated USING (true);
  CREATE POLICY "Only admins can modify platform settings" ON platform_settings
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'coa_employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'coa_employee')));
EXCEPTION WHEN others THEN NULL; END $$;

-- ── wallet_transactions ────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can insert wallet transactions" ON wallet_transactions;
  DROP POLICY IF EXISTS "Users can insert own wallet transactions" ON wallet_transactions;
  DROP POLICY IF EXISTS "Users can view own wallet transactions" ON wallet_transactions;
  CREATE POLICY "Users can insert own wallet transactions" ON wallet_transactions
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "Users can view own wallet transactions" ON wallet_transactions
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── audit_logs ─────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can insert audit logs" ON audit_logs;
  DROP POLICY IF EXISTS "System can insert audit logs" ON audit_logs;
  DROP POLICY IF EXISTS "Authenticated users can view audit logs" ON audit_logs;
  DROP POLICY IF EXISTS "Admins can view audit logs" ON audit_logs;
  CREATE POLICY "System can insert audit logs" ON audit_logs
    FOR INSERT TO authenticated
    WITH CHECK (true);
  CREATE POLICY "Admins can view audit logs" ON audit_logs
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'pastor', 'coa_employee')));
EXCEPTION WHEN others THEN NULL; END $$;

-- ── service_reports ────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can insert service reports" ON service_reports;
  DROP POLICY IF EXISTS "Pastors can insert service reports" ON service_reports;
  DROP POLICY IF EXISTS "Authenticated users can view service reports" ON service_reports;
  CREATE POLICY "Pastors can insert service reports" ON service_reports
    FOR INSERT TO authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('pastor', 'bishop', 'superadmin', 'admin')));
  CREATE POLICY "Authenticated users can view service reports" ON service_reports
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── pastor_reports ─────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can insert pastor reports" ON pastor_reports;
  DROP POLICY IF EXISTS "Pastors can insert own pastor reports" ON pastor_reports;
  DROP POLICY IF EXISTS "Authenticated users can view pastor reports" ON pastor_reports;
  CREATE POLICY "Pastors can insert own pastor reports" ON pastor_reports
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = pastor_id);
  CREATE POLICY "Authenticated users can view pastor reports" ON pastor_reports
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── testimonies ────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update testimonies" ON testimonies;
  DROP POLICY IF EXISTS "Authors can update own testimonies" ON testimonies;
  CREATE POLICY "Authors can update own testimonies" ON testimonies
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── prayers ────────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update prayers" ON prayers;
  DROP POLICY IF EXISTS "Authors can update own prayers" ON prayers;
  CREATE POLICY "Authors can update own prayers" ON prayers
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── social_posts ───────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update social_posts" ON social_posts;
  DROP POLICY IF EXISTS "Authors can update own social posts" ON social_posts;
  CREATE POLICY "Authors can update own social posts" ON social_posts
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── radio_stations ─────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can manage radio_stations" ON radio_stations;
  DROP POLICY IF EXISTS "Authenticated users can view radio_stations" ON radio_stations;
  DROP POLICY IF EXISTS "Admins can manage radio_stations" ON radio_stations;
  CREATE POLICY "Authenticated users can view radio_stations" ON radio_stations
    FOR SELECT TO authenticated USING (true);
  CREATE POLICY "Admins can manage radio_stations" ON radio_stations
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'coa_employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'coa_employee')));
EXCEPTION WHEN others THEN NULL; END $$;

-- ── messages ───────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view messages" ON messages;
  DROP POLICY IF EXISTS "Users can view messages in their conversations" ON messages;
  CREATE POLICY "Users can view messages in their conversations" ON messages
    FOR SELECT TO authenticated
    USING (
      EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = messages.conversation_id AND user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM group_members WHERE group_id = messages.group_id AND user_id = auth.uid())
    );
EXCEPTION WHEN others THEN NULL; END $$;
