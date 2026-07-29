-- ═══════════════════════════════════════════════════════════════
-- Final fixes: RLS + orphan table scoping
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Fix RLS on achievements ───────────────────────────────────
ALTER TABLE IF EXISTS public.achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "achievements_select" ON public.achievements;
DROP POLICY IF EXISTS "achievements_insert" ON public.achievements;
DO $$ BEGIN CREATE POLICY "achievements_select" ON public.achievements FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "achievements_insert" ON public.achievements FOR INSERT WITH CHECK (auth.role() = 'authenticated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Fix RLS on daily_challenges ───────────────────────────────
ALTER TABLE IF EXISTS public.daily_challenges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "daily_challenges_select" ON public.daily_challenges;
DROP POLICY IF EXISTS "daily_challenges_insert" ON public.daily_challenges;
DO $$ BEGIN CREATE POLICY "daily_challenges_select" ON public.daily_challenges FOR SELECT USING (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "daily_challenges_insert" ON public.daily_challenges FOR INSERT WITH CHECK (auth.role() = 'authenticated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 3. Add tenant_id + church_id to priority orphan tables ──────
-- These are church-content tables that need scoping

-- Marketplace
ALTER TABLE IF EXISTS public.marketplace_items ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.marketplace_items ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.marketplace_reviews ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.marketplace_reviews ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Media
ALTER TABLE IF EXISTS public.klips ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.klips ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.klip_comments ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.klip_comments ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.bible_audio_files ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.bible_audio_files ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.kingdom_news ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.kingdom_news ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Discipleship
ALTER TABLE IF EXISTS public.discipleship_milestones ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.discipleship_milestones ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.discipleship_relationships ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.discipleship_relationships ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Events
ALTER TABLE IF EXISTS public.event_registrations ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.event_registrations ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.event_resources ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.event_resources ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Sermons
ALTER TABLE IF EXISTS public.sermon_reactions ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.sermon_reactions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.service_ratings ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.service_ratings ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Social
ALTER TABLE IF EXISTS public.social_comments ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.social_comments ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.social_likes ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.social_likes ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Chat
ALTER TABLE IF EXISTS public.chat_messages ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.chat_messages ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.messages ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.messages ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Meetings
ALTER TABLE IF EXISTS public.meeting_notes ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.meeting_notes ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.meeting_participants ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.meeting_participants ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.calls ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.calls ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.call_candidates ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.call_candidates ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- AI
ALTER TABLE IF EXISTS public.ai_chat_messages ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ai_chat_messages ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ai_chat_sessions ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ai_chat_sessions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Quizzes
ALTER TABLE IF EXISTS public.quiz_events ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.quiz_events ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_answer_log ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.quiz_answer_log ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_weekly_scores ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.quiz_weekly_scores ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_streaks ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.quiz_streaks ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.pvp_answers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.pvp_answers ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.pvp_matches ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Fundraising
ALTER TABLE IF EXISTS public.fundraising_invites ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.fundraising_invites ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Groups
ALTER TABLE IF EXISTS public.group_members ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.group_members ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ministry_members ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ministry_members ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.community_group_members ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.community_group_members ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.group_contribution_members ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.group_contribution_members ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.group_contribution_payments ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.group_contribution_payments ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Logistics
ALTER TABLE IF EXISTS public.deliveries ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.deliveries ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.delivery_requests ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.delivery_requests ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ride_history ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ride_history ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ride_requests ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ride_requests ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ride_registrations ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.ride_registrations ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Payouts
ALTER TABLE IF EXISTS public.payout_requests ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.payout_requests ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.payout_approvers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.payout_approvers ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Prayers & Testimonies
ALTER TABLE IF EXISTS public.prayers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.prayers ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.testimonies ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.testimonies ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Tickets & SOS
ALTER TABLE IF EXISTS public.tickets ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.tickets ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.sos_alerts ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.sos_alerts ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Kids
ALTER TABLE IF EXISTS public.kids_zone_resources ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.kids_zone_resources ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Fasting
ALTER TABLE IF EXISTS public.fasting_plans ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.fasting_plans ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.fasting_schedules ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.fasting_schedules ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.fasting_subscriptions ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.fasting_subscriptions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Pastor reports
ALTER TABLE IF EXISTS public.pastor_reports ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.pastor_reports ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Jobs
ALTER TABLE IF EXISTS public.job_applications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.job_applications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.job_notifications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.job_notifications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.driver_applications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.driver_applications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.writer_applications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.writer_applications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Bible study extras
ALTER TABLE IF EXISTS public.reading_plans ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.reading_plans ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.devotions ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.devotions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.daily_bible_verses ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.daily_bible_verses ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Resource allocation & routing
ALTER TABLE IF EXISTS public.resource_allocations ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.resource_allocations ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.route_optimizations ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.route_optimizations ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- Referrals
ALTER TABLE IF EXISTS public.referrals ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.referrals ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- ═══════════════════════════════════════════════════════════════════
-- Verify (check 3 sample tables got their columns)
SELECT 'marketplace_items' AS tbl,
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'marketplace_items' AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped) AS has_tenant,
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'marketplace_items' AND a.attname = 'church_id' AND a.attnum > 0 AND NOT a.attisdropped) AS has_church
UNION ALL
SELECT 'discipleship_milestones',
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'discipleship_milestones' AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped),
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'discipleship_milestones' AND a.attname = 'church_id' AND a.attnum > 0 AND NOT a.attisdropped)
UNION ALL
SELECT 'sos_alerts',
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'sos_alerts' AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped),
       EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = 'sos_alerts' AND a.attname = 'church_id' AND a.attnum > 0 AND NOT a.attisdropped);
