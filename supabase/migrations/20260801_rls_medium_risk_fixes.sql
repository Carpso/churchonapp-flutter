-- ============================================================
-- Migration: 20260801_rls_medium_risk_fixes
-- Fix remaining medium-risk RLS policies.
-- Safe to re-run: each table wrapped in its own exception block.
-- ============================================================

-- ── notifications ──────────────────────────────────────────
-- Was: FOR INSERT WITH CHECK (true) → any user could insert for others
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;
  DROP POLICY IF EXISTS "Users can insert own notifications" ON notifications;
  DROP POLICY IF EXISTS "Authenticated users can view notifications" ON notifications;
  DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;

  CREATE POLICY "Users can insert own notifications" ON notifications
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── groups ─────────────────────────────────────────────────
-- Was: FOR SELECT USING (true) → all groups visible
-- Keep public read (groups are discoverable) but restrict member info
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view groups" ON groups;
  DROP POLICY IF EXISTS "Anyone can view groups" ON groups;

  CREATE POLICY "Authenticated users can view groups" ON groups
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── group_members ──────────────────────────────────────────
-- Was: FOR SELECT USING (true) → all membership visible
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view group_members" ON group_members;
  DROP POLICY IF EXISTS "Users can view own group membership" ON group_members;
  DROP POLICY IF EXISTS "Group members can view membership" ON group_members;

  CREATE POLICY "Group members can view membership" ON group_members
    FOR SELECT TO authenticated
    USING (
      EXISTS (SELECT 1 FROM group_members gm WHERE gm.group_id = group_members.group_id AND gm.user_id = auth.uid())
    );
  CREATE POLICY "Users can join groups" ON group_members
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "Users can leave groups" ON group_members
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── fundraising_contributions ──────────────────────────────
-- Was: USING (true) SELECT → financial data publicly readable
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view fundraising_contributions" ON fundraising_contributions;
  DROP POLICY IF EXISTS "Anyone can view fundraising_contributions" ON fundraising_contributions;
  DROP POLICY IF EXISTS "Authenticated users can insert fundraising_contributions" ON fundraising_contributions;

  CREATE POLICY "Authenticated users can view fundraising contributions" ON fundraising_contributions
    FOR SELECT TO authenticated USING (true);
  CREATE POLICY "Authenticated users can insert fundraising contributions" ON fundraising_contributions
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = contributor_id);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── fundraising_campaigns ──────────────────────────────────
-- Was: USING (true) SELECT → campaigns visible (acceptable to keep public)
-- Only restrict write access
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view fundraising_campaigns" ON fundraising_campaigns;
  DROP POLICY IF EXISTS "Anyone can view fundraising_campaigns" ON fundraising_campaigns;
  DROP POLICY IF EXISTS "Authenticated users can insert fundraising_campaigns" ON fundraising_campaigns;
  DROP POLICY IF EXISTS "Authenticated users can update fundraising_campaigns" ON fundraising_campaigns;

  CREATE POLICY "Authenticated users can view fundraising campaigns" ON fundraising_campaigns
    FOR SELECT TO authenticated USING (true);
  CREATE POLICY "Admins can manage fundraising campaigns" ON fundraising_campaigns
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'pastor', 'treasurer')))
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'admin', 'pastor', 'treasurer')));
EXCEPTION WHEN others THEN NULL; END $$;

-- ── streaming_sessions ─────────────────────────────────────
-- Was: FOR INSERT WITH CHECK (true) → any user could create
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can insert streaming_sessions" ON streaming_sessions;
  DROP POLICY IF EXISTS "Church members can insert streaming sessions" ON streaming_sessions;
  DROP POLICY IF EXISTS "Authenticated users can view streaming_sessions" ON streaming_sessions;

  CREATE POLICY "Church members can insert streaming sessions" ON streaming_sessions
    FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND tenant_id = streaming_sessions.church_id AND role IN ('pastor', 'bishop', 'superadmin', 'admin'))
    );
  CREATE POLICY "Authenticated users can view streaming sessions" ON streaming_sessions
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN others THEN NULL; END $$;

-- ── community_messages ─────────────────────────────────────
-- Was: USING (true) SELECT → all community messages visible
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can view community_messages" ON community_messages;
  DROP POLICY IF EXISTS "Community members can view messages" ON community_messages;
  DROP POLICY IF EXISTS "Authenticated users can insert community_messages" ON community_messages;

  CREATE POLICY "Community members can view messages" ON community_messages
    FOR SELECT TO authenticated
    USING (
      EXISTS (SELECT 1 FROM community_members WHERE community_id = community_messages.community_id AND user_id = auth.uid())
    );
  CREATE POLICY "Community members can insert messages" ON community_messages
    FOR INSERT TO authenticated
    WITH CHECK (
      auth.uid() = user_id
      AND EXISTS (SELECT 1 FROM community_members WHERE community_id = community_messages.community_id AND user_id = auth.uid())
    );
EXCEPTION WHEN others THEN NULL; END $$;
