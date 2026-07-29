-- ═══════════════════════════════════════════════════════════════
-- Add church_id + tenant_id to all church-scoped tables
-- Architecture: tenant_id = billing/subscription entity,
--               church_id = specific church/location
-- ═══════════════════════════════════════════════════════════════

-- ── Add church_id to tables that have tenant_id but not church_id ──

ALTER TABLE IF EXISTS public.attendance_logs ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.bible_study_sessions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.business_meetings ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.church_bus_routes ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.church_buses ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.community_communities ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.community_groups ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.discipleship_plans ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.emergency_contacts ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.events ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.flyers ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.fundraising_contributions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.fundraising_ventures ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.group_contributions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.live_chat_messages ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.ministries ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.news ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.notifications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.orders ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.parking_zones ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.payment_logs ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.pending_payments ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.pledges ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.profiles ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quick_routes ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_season_leaderboard ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_seasons ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.quiz_weekly_challenges ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.role_assignments ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.service_reports ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.social_posts ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.tenant_ads ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.tenant_roles ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.tithe_cards ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.tithe_records ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.traffic_alerts ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.transactions ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.worship_lyrics ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE IF EXISTS public.year_planner ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- ── Add tenant_id to tables that have church_id but not tenant_id ──

ALTER TABLE IF EXISTS public.channels ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.church_live_status ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.church_quiz_competitions ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.church_quiz_leases ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.event_participating_churches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.groups ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.jobs ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.network_activity ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.pastors_corner ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.quiz_passes ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.sermons ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);

-- ── Add both tenant_id + church_id to new tables that have neither ──

ALTER TABLE IF EXISTS public.game_scores ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.game_scores ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

ALTER TABLE IF EXISTS public.kids_progress ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE IF EXISTS public.kids_progress ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- ── Verify ──────────────────────────────────────────────────────
SELECT table_name, 
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = t.table_name AND column_name = 'tenant_id') AS has_tenant_id,
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = t.table_name AND column_name = 'church_id') AS has_church_id
FROM (SELECT unnest(ARRAY[
  'emergency_contacts','discipleship_plans','church_bus_routes','bible_study_sessions',
  'game_scores','kids_progress','events','notifications','year_planner',
  'sermons','groups','jobs','profiles'
]) AS table_name) t;
