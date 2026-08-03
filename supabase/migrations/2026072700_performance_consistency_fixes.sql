-- ════════════════════════════════════════════════════════════════
-- Performance + consistency fixes
-- Fixes type mismatches, adds missing indexes
-- ════════════════════════════════════════════════════════════════

-- =============================================================================
-- PART 1: Fix tenant_id type inconsistency (TEXT → UUID)
-- service_reports.tenant_id and social_posts.tenant_id are TEXT while every
-- other table uses UUID — breaks FK enforcement and hurts join performance.
-- Existing RLS policies continue to work (::uuid casts become redundant but
-- harmless once both sides are UUID).
-- =============================================================================

-- 1a. service_reports.tenant_id: TEXT → UUID
-- Must drop RLS policies first (they depend on the column), then recreate
DO $$
DECLARE
  col_type TEXT;
BEGIN
  SELECT data_type INTO col_type FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'service_reports' AND column_name = 'tenant_id';

  IF col_type IN ('text', 'character varying') THEN
    DROP POLICY IF EXISTS "Tenant members can view service reports" ON public.service_reports;
    DROP POLICY IF EXISTS "Authenticated users can submit service reports" ON public.service_reports;
    DROP POLICY IF EXISTS "Anyone can view service reports" ON public.service_reports;
    DROP POLICY IF EXISTS "Pastors can submit service reports" ON public.service_reports;
    DROP POLICY IF EXISTS "Authenticated users can insert service reports" ON public.service_reports;

    ALTER TABLE service_reports ADD COLUMN tenant_id_uuid UUID;
    UPDATE service_reports SET tenant_id_uuid = tenant_id::uuid
    WHERE tenant_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    DELETE FROM service_reports WHERE tenant_id_uuid IS NULL;
    ALTER TABLE service_reports DROP COLUMN tenant_id;
    ALTER TABLE service_reports RENAME COLUMN tenant_id_uuid TO tenant_id;
    ALTER TABLE service_reports ALTER COLUMN tenant_id SET NOT NULL;
    ALTER TABLE service_reports ADD CONSTRAINT fk_service_reports_tenant
      FOREIGN KEY (tenant_id) REFERENCES churches(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Recreate service_reports RLS policies (runs unconditionally as top-level SQL;
-- DROP IF EXISTS is safe if the DO block already dropped them)
DROP POLICY IF EXISTS "Tenant members can view service reports" ON public.service_reports;
CREATE POLICY "Tenant members can view service reports"
  ON public.service_reports FOR SELECT
  USING (
    tenant_id IS NULL OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id::text = auth.uid()::text AND tenant_id::text = service_reports.tenant_id::text
    )
  );
DROP POLICY IF EXISTS "Authenticated users can submit service reports" ON public.service_reports;
CREATE POLICY "Authenticated users can submit service reports"
  ON public.service_reports FOR INSERT
  WITH CHECK (auth.uid()::text = reporter_id::text);

-- 1b. social_posts.tenant_id: TEXT → UUID
DO $$
DECLARE
  col_type TEXT;
BEGIN
  SELECT data_type INTO col_type FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'social_posts' AND column_name = 'tenant_id';

  IF col_type IN ('text', 'character varying') THEN
    ALTER TABLE social_posts ADD COLUMN tenant_id_uuid UUID;
    UPDATE social_posts SET tenant_id_uuid = tenant_id::uuid
    WHERE tenant_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    DELETE FROM social_posts WHERE tenant_id_uuid IS NULL;
    ALTER TABLE social_posts DROP COLUMN tenant_id;
    ALTER TABLE social_posts RENAME COLUMN tenant_id_uuid TO tenant_id;
    ALTER TABLE social_posts ADD CONSTRAINT fk_social_posts_tenant
      FOREIGN KEY (tenant_id) REFERENCES churches(id) ON DELETE CASCADE;
  END IF;
END $$;

-- =============================================================================
-- PART 2: Critical missing indexes
-- =============================================================================

-- 2a. wallet_transactions — queried by user_id ~8x, NO INDEX (CRITICAL)
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_created ON wallet_transactions(created_at DESC);

-- 2b. events — filtered by tenant_id, date, category
CREATE INDEX IF NOT EXISTS idx_events_tenant_id ON events(tenant_id);
CREATE INDEX IF NOT EXISTS idx_events_date ON events(date);
CREATE INDEX IF NOT EXISTS idx_events_category ON events(category);
CREATE INDEX IF NOT EXISTS idx_events_tenant_dates ON events(tenant_id, date DESC);

-- 2c. sermons — filtered by church_id and is_live
CREATE INDEX IF NOT EXISTS idx_sermons_church_id ON sermons(church_id);
CREATE INDEX IF NOT EXISTS idx_sermons_live ON sermons(is_live) WHERE is_live = true;
CREATE INDEX IF NOT EXISTS idx_sermons_created ON sermons(created_at DESC);

-- 2d. delivery_requests — filtered by sender_id, driver_id, status
CREATE INDEX IF NOT EXISTS idx_delivery_sender ON delivery_requests(sender_id);
CREATE INDEX IF NOT EXISTS idx_delivery_driver ON delivery_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_delivery_status ON delivery_requests(status);
CREATE INDEX IF NOT EXISTS idx_delivery_created ON delivery_requests(created_at DESC);

-- 2e. channels — church_id for channel list
CREATE INDEX IF NOT EXISTS idx_channels_church ON channels(church_id);

-- 2f. messages — channel_id for chat load + user history
CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages(channel_id);
CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_channel_created ON messages(channel_id, created_at);

-- 2g. groups — church_id for group discovery
CREATE INDEX IF NOT EXISTS idx_groups_church ON groups(church_id);

-- 2h. social_posts — feed queries sorted by time
CREATE INDEX IF NOT EXISTS idx_social_posts_created ON social_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_social_posts_tenant_created ON social_posts(tenant_id, created_at DESC);

-- 2i. social_comments — comments per post + user history
CREATE INDEX IF NOT EXISTS idx_social_comments_post ON social_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_social_comments_user ON social_comments(user_id);

-- 2j. tickets — event + user lookups
CREATE INDEX IF NOT EXISTS idx_tickets_event ON tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_user ON tickets(user_id);

-- 2k. notifications — time ordering for inbox
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id, created_at DESC);

-- 2l. testimonies — time-ordered feeds
CREATE INDEX IF NOT EXISTS idx_testimonies_created ON testimonies(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_testimonies_user_created ON testimonies(user_id, created_at DESC);

-- 2m. prayers — feed + user history
CREATE INDEX IF NOT EXISTS idx_prayers_feed ON prayers(visibility, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prayers_user_created ON prayers(user_id, created_at DESC);

-- 2n. klips — user history
CREATE INDEX IF NOT EXISTS idx_klips_user_created ON klips(user_id, created_at DESC);

-- 2o. orders — tenant + time for marketplace dashboards
CREATE INDEX IF NOT EXISTS idx_orders_tenant_created ON orders(tenant_id, created_at DESC);

-- 2p. transactions — tenant + time for finance dashboards
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_created ON transactions(tenant_id, created_at DESC);

-- 2q. marketplace_items — category + status for browsing
CREATE INDEX IF NOT EXISTS idx_marketplace_items_category_status ON marketplace_items(category, status);

-- 2r. payout_requests — finance ops
CREATE INDEX IF NOT EXISTS idx_payouts_user ON payout_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_payouts_status ON payout_requests(status);

-- 2s. lenco_payouts — payout tracking
CREATE INDEX IF NOT EXISTS idx_lenco_payouts_user ON lenco_payouts(user_id);
CREATE INDEX IF NOT EXISTS idx_lenco_payouts_status ON lenco_payouts(status);

-- 2t. kyc_documents — verification flow
CREATE INDEX IF NOT EXISTS idx_kyc_user_status ON kyc_documents(user_id, status);

-- 2u. user_activities — per-user timeline
CREATE INDEX IF NOT EXISTS idx_user_activities_user_created ON user_activities(user_id, created_at DESC);

-- =============================================================================
-- PART 3: Composite indexes for common tenant access patterns
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_attendance_logs_tenant_date ON attendance_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_church_buses_tenant ON church_buses(tenant_id);
CREATE INDEX IF NOT EXISTS idx_flyers_tenant ON flyers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ministries_tenant ON ministries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_parking_zones_tenant ON parking_zones(tenant_id);
CREATE INDEX IF NOT EXISTS idx_quick_routes_tenant ON quick_routes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_traffic_alerts_tenant ON traffic_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_service_reports_tenant ON service_reports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_service_reports_tenant_created ON service_reports(tenant_id, created_at DESC);

-- =============================================================================
-- PART 4: Add search indexes for frequently filtered text columns
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_sermons_preacher ON sermons(preacher);
CREATE INDEX IF NOT EXISTS idx_sermons_title ON sermons(title);
CREATE INDEX IF NOT EXISTS idx_marketplace_items_name ON marketplace_items(name);
CREATE INDEX IF NOT EXISTS idx_social_posts_category ON social_posts(category);
