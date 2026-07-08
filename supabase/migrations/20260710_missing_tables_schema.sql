-- ═══════════════════════════════════════════════════════════════════════════════
-- MISSING TABLES MIGRATION
-- Creates all 45 tables referenced in Dart code but missing from SQL migrations
-- Uses CREATE TABLE IF NOT EXISTS for safe re-runs
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0. Backfill columns on pre-existing tables before any policies reference them
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'jobs') THEN
    EXECUTE 'ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''active''';
    EXECUTE 'ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS type TEXT DEFAULT ''Full-time''';
    EXECUTE 'ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS employer_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'marketplace_items') THEN
    EXECUTE 'ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''active''';
    EXECUTE 'ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS market_type TEXT DEFAULT ''general''';
    EXECUTE 'ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS is_curated BOOLEAN DEFAULT false';
    EXECUTE 'ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS condition TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'news') THEN
    EXECUTE 'ALTER TABLE public.news ADD COLUMN IF NOT EXISTS excerpt TEXT';
    EXECUTE 'ALTER TABLE public.news ADD COLUMN IF NOT EXISTS category TEXT DEFAULT ''General''';
    EXECUTE 'ALTER TABLE public.news ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'devotions') THEN
    EXECUTE 'ALTER TABLE public.devotions ADD COLUMN IF NOT EXISTS reference TEXT';
    EXECUTE 'ALTER TABLE public.devotions ADD COLUMN IF NOT EXISTS scripture_text TEXT';
    EXECUTE 'ALTER TABLE public.devotions ADD COLUMN IF NOT EXISTS reflection TEXT';
    EXECUTE 'ALTER TABLE public.devotions ADD COLUMN IF NOT EXISTS prayer TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'klips') THEN
    EXECUTE 'ALTER TABLE public.klips ADD COLUMN IF NOT EXISTS amen_count INTEGER DEFAULT 0';
    EXECUTE 'ALTER TABLE public.klips ADD COLUMN IF NOT EXISTS comments_count INTEGER DEFAULT 0';
    EXECUTE 'ALTER TABLE public.klips ADD COLUMN IF NOT EXISTS share_count INTEGER DEFAULT 0';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'kingdom_news') THEN
    EXECUTE 'ALTER TABLE public.kingdom_news ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''published''';
    EXECUTE 'ALTER TABLE public.kingdom_news ADD COLUMN IF NOT EXISTS author_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.kingdom_news ADD COLUMN IF NOT EXISTS excerpt TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    EXECUTE 'ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now()';
    EXECUTE 'ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL';
    EXECUTE 'ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS totp_secret TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'events') THEN
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS hosted_by UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS host_type TEXT DEFAULT ''church''';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS is_paid_event BOOLEAN DEFAULT false';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_price DOUBLE PRECISION';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_limit INTEGER';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS tickets_sold INTEGER DEFAULT 0';
    EXECUTE 'ALTER TABLE public.events ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sermons') THEN
    EXECUTE 'ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id)';
    EXECUTE 'ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS transcript TEXT';
    EXECUTE 'ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS ai_summary TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'notifications') THEN
    EXECUTE 'ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT';
    EXECUTE 'ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS reference_id TEXT';
    EXECUTE 'ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallet_transactions') THEN
    EXECUTE 'ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS category TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tickets') THEN
    EXECUTE 'ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS event_id UUID REFERENCES public.events(id)';
    EXECUTE 'ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'channels') THEN
    EXECUTE 'ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'messages') THEN
    EXECUTE 'ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS channel_id UUID REFERENCES public.channels(id)';
    EXECUTE 'ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS content TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'groups') THEN
    EXECUTE 'ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id)';
    EXECUTE 'ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'group_members') THEN
    EXECUTE 'ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.groups(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'payout_requests') THEN
    EXECUTE 'ALTER TABLE public.payout_requests ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tithe_records') THEN
    EXECUTE 'ALTER TABLE public.tithe_records ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ride_requests') THEN
    EXECUTE 'ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS rider_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS driver_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'delivery_requests') THEN
    EXECUTE 'ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS sender_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.delivery_requests ADD COLUMN IF NOT EXISTS driver_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'churches') THEN
    EXECUTE 'ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMPTZ';
    EXECUTE 'ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ';
    EXECUTE 'ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT ''trial''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'social_posts') THEN
    EXECUTE 'ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.social_posts ADD COLUMN IF NOT EXISTS is_moderated BOOLEAN DEFAULT false';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'social_likes') THEN
    EXECUTE 'ALTER TABLE public.social_likes ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'social_comments') THEN
    EXECUTE 'ALTER TABLE public.social_comments ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sms_logs') THEN
    EXECUTE 'ALTER TABLE public.sms_logs ADD COLUMN IF NOT EXISTS recipient TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'growth_heatmap_data') THEN
    EXECUTE 'ALTER TABLE public.growth_heatmap_data ADD COLUMN IF NOT EXISTS data JSONB DEFAULT ''{}''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'resource_allocations') THEN
    EXECUTE 'ALTER TABLE public.resource_allocations ADD COLUMN IF NOT EXISTS resource_type TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'lenco_payouts') THEN
    EXECUTE 'ALTER TABLE public.lenco_payouts ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expansion_leads') THEN
    EXECUTE 'ALTER TABLE public.expansion_leads ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''new''';
    EXECUTE 'ALTER TABLE public.expansion_leads ADD COLUMN IF NOT EXISTS interest_type TEXT DEFAULT ''notify_on_registration''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'feature_requests') THEN
    EXECUTE 'ALTER TABLE public.feature_requests ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''pending''';
    EXECUTE 'ALTER TABLE public.feature_requests ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT ''Medium''';
    EXECUTE 'ALTER TABLE public.feature_requests ADD COLUMN IF NOT EXISTS category TEXT DEFAULT ''Other''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'flyers') THEN
    EXECUTE 'ALTER TABLE public.flyers ADD COLUMN IF NOT EXISTS created_by TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'job_applications') THEN
    EXECUTE 'ALTER TABLE public.job_applications ADD COLUMN IF NOT EXISTS status TEXT DEFAULT ''pending''';
    EXECUTE 'ALTER TABLE public.job_applications ADD COLUMN IF NOT EXISTS applicant_name TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'klip_comments') THEN
    EXECUTE 'ALTER TABLE public.klip_comments ADD COLUMN IF NOT EXISTS content TEXT';  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'live_chat_messages') THEN
    EXECUTE 'ALTER TABLE public.live_chat_messages ADD COLUMN IF NOT EXISTS content TEXT';
    EXECUTE 'ALTER TABLE public.live_chat_messages ADD COLUMN IF NOT EXISTS user_name TEXT';
    EXECUTE 'ALTER TABLE public.live_chat_messages ADD COLUMN IF NOT EXISTS user_photo TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'meeting_notes') THEN
    EXECUTE 'ALTER TABLE public.meeting_notes ADD COLUMN IF NOT EXISTS content TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'meeting_votes') THEN
    EXECUTE 'ALTER TABLE public.meeting_votes ADD COLUMN IF NOT EXISTS option_selected TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ministries') THEN
    EXECUTE 'ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS description TEXT';
    EXECUTE 'ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS meeting_day TEXT';
    EXECUTE 'ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS meeting_time TEXT';
    EXECUTE 'ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS meeting_location TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'network_activity') THEN
    EXECUTE 'ALTER TABLE public.network_activity ADD COLUMN IF NOT EXISTS description TEXT';
    EXECUTE 'ALTER TABLE public.network_activity ADD COLUMN IF NOT EXISTS reference_id TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'organizations') THEN
    EXECUTE 'ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS bishop_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS secretary_id UUID REFERENCES auth.users(id)';
    EXECUTE 'ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS treasurer_id UUID REFERENCES auth.users(id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'parking_zones') THEN
    EXECUTE 'ALTER TABLE public.parking_zones ADD COLUMN IF NOT EXISTS available INTEGER DEFAULT 0';
    EXECUTE 'ALTER TABLE public.parking_zones ADD COLUMN IF NOT EXISTS total INTEGER DEFAULT 0';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pastors_corner') THEN
    EXECUTE 'ALTER TABLE public.pastors_corner ADD COLUMN IF NOT EXISTS excerpt TEXT';
    EXECUTE 'ALTER TABLE public.pastors_corner ADD COLUMN IF NOT EXISTS content TEXT';
    EXECUTE 'ALTER TABLE public.pastors_corner ADD COLUMN IF NOT EXISTS pastor_name TEXT';
    EXECUTE 'ALTER TABLE public.pastors_corner ADD COLUMN IF NOT EXISTS pastor_photo TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'quick_routes') THEN
    EXECUTE 'ALTER TABLE public.quick_routes ADD COLUMN IF NOT EXISTS time TEXT';
    EXECUTE 'ALTER TABLE public.quick_routes ADD COLUMN IF NOT EXISTS via TEXT';
    EXECUTE 'ALTER TABLE public.quick_routes ADD COLUMN IF NOT EXISTS icon TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reading_plans') THEN
    EXECUTE 'ALTER TABLE public.reading_plans ADD COLUMN IF NOT EXISTS description TEXT';
    EXECUTE 'ALTER TABLE public.reading_plans ADD COLUMN IF NOT EXISTS daily_verses JSONB DEFAULT ''[]''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ride_registrations') THEN
    EXECUTE 'ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS vehicle_info TEXT';
    EXECUTE 'ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS pre_registered_name TEXT';
    EXECUTE 'ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS pre_registered_phone TEXT';
    EXECUTE 'ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS pre_registered_role TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sermon_reactions') THEN
    EXECUTE 'ALTER TABLE public.sermon_reactions ADD COLUMN IF NOT EXISTS content TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'traffic_alerts') THEN
    EXECUTE 'ALTER TABLE public.traffic_alerts ADD COLUMN IF NOT EXISTS description TEXT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_fasts') THEN
    EXECUTE 'ALTER TABLE public.user_fasts ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_notes') THEN
    EXECUTE 'ALTER TABLE public.user_notes ADD COLUMN IF NOT EXISTS topic TEXT';
    EXECUTE 'ALTER TABLE public.user_notes ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT false';
    EXECUTE 'ALTER TABLE public.user_notes ADD COLUMN IF NOT EXISTS category TEXT DEFAULT ''general''';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'year_planner') THEN
    EXECUTE 'ALTER TABLE public.year_planner ADD COLUMN IF NOT EXISTS description TEXT';
    EXECUTE 'ALTER TABLE public.year_planner ADD COLUMN IF NOT EXISTS is_central BOOLEAN DEFAULT false';
  END IF;
END $$;

-- 1. PROFILES (commonly created by auth trigger, but needs explicit definition)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    role TEXT DEFAULT 'member',
    coins INTEGER DEFAULT 500,
    streak_count INTEGER DEFAULT 0,
    last_read_at TIMESTAMPTZ,
    is_work_mode BOOLEAN DEFAULT false,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    balance_cc NUMERIC DEFAULT 0,
    balance_zmw NUMERIC DEFAULT 0,
    phone_number TEXT,
    tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,
    is_verified BOOLEAN DEFAULT false,
    kyc_status TEXT DEFAULT 'unverified',
    referral_code TEXT,
    fcm_token TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
CREATE POLICY "Users can read own profile" ON public.profiles
    FOR SELECT TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Anyone can view basic profile info" ON public.profiles;
CREATE POLICY "Anyone can view basic profile info" ON public.profiles
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;
CREATE POLICY "Superadmins and employees can manage all profiles" ON public.profiles
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_tenant ON public.profiles(tenant_id);

-- 2. TRANSACTIONS
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount NUMERIC NOT NULL,
    category TEXT DEFAULT 'giving',
    status TEXT DEFAULT 'pending',
    reference TEXT,
    tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,
    platform_fee NUMERIC DEFAULT 0,
    recipient_name TEXT,
    recipient_phone TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own transactions" ON public.transactions;
CREATE POLICY "Users can view own transactions" ON public.transactions
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own transactions" ON public.transactions;
CREATE POLICY "Users can create own transactions" ON public.transactions
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Leaders can view church transactions" ON public.transactions;
CREATE POLICY "Leaders can view church transactions" ON public.transactions
    FOR SELECT TO authenticated USING (
        tenant_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.tenant_id::uuid = transactions.tenant_id
            AND p.role IN ('admin', 'pastor', 'bishop', 'general_treasurer', 'general_secretary', 'superadmin', 'employee')
        )
    );

DROP POLICY IF EXISTS "Superadmins can manage all transactions" ON public.transactions;
CREATE POLICY "Superadmins can manage all transactions" ON public.transactions
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_transactions_user ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant ON public.transactions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_transactions_reference ON public.transactions(reference);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);

-- 3. PRAYERS
CREATE TABLE IF NOT EXISTS public.prayers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT,
    user_photo TEXT,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'other',
    visibility TEXT DEFAULT 'public',
    prayer_count INTEGER DEFAULT 1,
    prayed_by JSONB DEFAULT '[]',
    is_anonymous BOOLEAN DEFAULT false,
    ai_encouragement TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.prayers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read prayers" ON public.prayers;
CREATE POLICY "Anyone can read prayers" ON public.prayers
    FOR SELECT TO authenticated USING (visibility = 'public' OR auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create prayers" ON public.prayers;
CREATE POLICY "Users can create prayers" ON public.prayers
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own prayers" ON public.prayers;
CREATE POLICY "Users can update own prayers" ON public.prayers
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own prayers" ON public.prayers;
CREATE POLICY "Users can delete own prayers" ON public.prayers
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate prayers" ON public.prayers;
CREATE POLICY "Superadmins can moderate prayers" ON public.prayers
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_prayers_user ON public.prayers(user_id);
CREATE INDEX IF NOT EXISTS idx_prayers_category ON public.prayers(category);
CREATE INDEX IF NOT EXISTS idx_prayers_visibility ON public.prayers(visibility);

-- 4. TESTIMONIES
CREATE TABLE IF NOT EXISTS public.testimonies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT,
    user_photo TEXT,
    content TEXT NOT NULL,
    image_url TEXT,
    praise_count INTEGER DEFAULT 0,
    praised_by JSONB DEFAULT '[]',
    category TEXT DEFAULT 'General',
    likes INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.testimonies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read testimonies" ON public.testimonies;
CREATE POLICY "Anyone can read testimonies" ON public.testimonies
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can create testimonies" ON public.testimonies;
CREATE POLICY "Users can create testimonies" ON public.testimonies
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own testimonies" ON public.testimonies;
CREATE POLICY "Users can update own testimonies" ON public.testimonies
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own testimonies" ON public.testimonies;
CREATE POLICY "Users can delete own testimonies" ON public.testimonies
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate testimonies" ON public.testimonies;
CREATE POLICY "Superadmins can moderate testimonies" ON public.testimonies
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_testimonies_user ON public.testimonies(user_id);
CREATE INDEX IF NOT EXISTS idx_testimonies_category ON public.testimonies(category);

-- 5. KLIPS
CREATE TABLE IF NOT EXISTS public.klips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT,
    description TEXT,
    video_url TEXT,
    thumbnail_url TEXT,
    speaker TEXT,
    church_name TEXT,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_name TEXT,
    user_avatar TEXT,
    views INTEGER DEFAULT 0,
    likes INTEGER DEFAULT 0,
    amen_count INTEGER DEFAULT 0,
    comments_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    liked_by JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.klips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read klips" ON public.klips;
CREATE POLICY "Anyone can read klips" ON public.klips
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can create klips" ON public.klips;
CREATE POLICY "Authenticated users can create klips" ON public.klips
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own klips" ON public.klips;
CREATE POLICY "Users can update own klips" ON public.klips
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own klips" ON public.klips;
CREATE POLICY "Users can delete own klips" ON public.klips
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate klips" ON public.klips;
CREATE POLICY "Superadmins can moderate klips" ON public.klips
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_klips_user ON public.klips(user_id);
CREATE INDEX IF NOT EXISTS idx_klips_created ON public.klips(created_at DESC);

-- 6. MARKETPLACE ITEMS
CREATE TABLE IF NOT EXISTS public.marketplace_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    price NUMERIC NOT NULL,
    category TEXT,
    image TEXT,
    description TEXT,
    vendor_name TEXT,
    vendor_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    condition TEXT,
    market_type TEXT DEFAULT 'general',
    is_curated BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.marketplace_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view marketplace items" ON public.marketplace_items;
CREATE POLICY "Anyone can view marketplace items" ON public.marketplace_items
    FOR SELECT TO authenticated USING (status = 'active');

DROP POLICY IF EXISTS "Vendors can create items" ON public.marketplace_items;
CREATE POLICY "Vendors can create items" ON public.marketplace_items
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = vendor_id);

DROP POLICY IF EXISTS "Vendors can update own items" ON public.marketplace_items;
CREATE POLICY "Vendors can update own items" ON public.marketplace_items
    FOR UPDATE TO authenticated USING (auth.uid() = vendor_id);

DROP POLICY IF EXISTS "Superadmins can manage all items" ON public.marketplace_items;
CREATE POLICY "Superadmins can manage all items" ON public.marketplace_items
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_marketplace_items_vendor ON public.marketplace_items(vendor_id);
CREATE INDEX IF NOT EXISTS idx_marketplace_items_category ON public.marketplace_items(category);
CREATE INDEX IF NOT EXISTS idx_marketplace_items_status ON public.marketplace_items(status);

-- 7. NEWS (tenant-specific news, distinct from kingdom_news)
CREATE TABLE IF NOT EXISTS public.news (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    excerpt TEXT,
    content TEXT,
    image_url TEXT,
    author_name TEXT,
    category TEXT DEFAULT 'General',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read news" ON public.news;
CREATE POLICY "Anyone can read news" ON public.news
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can create news" ON public.news;
CREATE POLICY "Tenant admins can create news" ON public.news
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = news.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Tenant admins can manage own news" ON public.news;
CREATE POLICY "Tenant admins can manage own news" ON public.news
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = news.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_news_tenant ON public.news(tenant_id);
CREATE INDEX IF NOT EXISTS idx_news_category ON public.news(category);

-- 8. DEVOTIONS
CREATE TABLE IF NOT EXISTS public.devotions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    reference TEXT,
    scripture_text TEXT,
    reflection TEXT,
    prayer TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.devotions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read devotions" ON public.devotions;
CREATE POLICY "Anyone can read devotions" ON public.devotions
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Writers and admins can create devotions" ON public.devotions;
CREATE POLICY "Writers and admins can create devotions" ON public.devotions
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('writer', 'admin', 'superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Writers and admins can update devotions" ON public.devotions;
CREATE POLICY "Writers and admins can update devotions" ON public.devotions
    FOR UPDATE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('writer', 'admin', 'superadmin', 'employee'))
    );


-- 9. JOBS
CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    company TEXT,
    location TEXT,
    type TEXT DEFAULT 'Full-time',
    description TEXT,
    salary TEXT,
    contact TEXT,
    employer_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read jobs" ON public.jobs;
CREATE POLICY "Anyone can read jobs" ON public.jobs
    FOR SELECT TO authenticated USING (status = 'active');

DROP POLICY IF EXISTS "Authenticated users can create jobs" ON public.jobs;
CREATE POLICY "Authenticated users can create jobs" ON public.jobs
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage own jobs" ON public.jobs;
CREATE POLICY "Users can manage own jobs" ON public.jobs
    FOR ALL TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can manage all jobs" ON public.jobs;
CREATE POLICY "Superadmins can manage all jobs" ON public.jobs
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_jobs_user ON public.jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_jobs_type ON public.jobs(type);

-- 10. KINGDOM NEWS
CREATE TABLE IF NOT EXISTS public.kingdom_news (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    author_name TEXT,
    excerpt TEXT,
    content TEXT,
    image_url TEXT,
    author_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'published',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kingdom_news ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read kingdom news" ON public.kingdom_news;
CREATE POLICY "Anyone can read kingdom news" ON public.kingdom_news
    FOR SELECT TO authenticated USING (status = 'published' OR auth.uid() = author_id);

DROP POLICY IF EXISTS "Writers and admins can create news" ON public.kingdom_news;
CREATE POLICY "Writers and admins can create news" ON public.kingdom_news
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('writer', 'admin', 'superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Authors can update own news" ON public.kingdom_news;
CREATE POLICY "Authors can update own news" ON public.kingdom_news
    FOR UPDATE TO authenticated USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "Superadmins can manage all news" ON public.kingdom_news;
CREATE POLICY "Superadmins can manage all news" ON public.kingdom_news
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_kingdom_news_author ON public.kingdom_news(author_id);
CREATE INDEX IF NOT EXISTS idx_kingdom_news_status ON public.kingdom_news(status);

-- 11. AI CHAT SESSIONS
CREATE TABLE IF NOT EXISTS public.ai_chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_chat_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own sessions" ON public.ai_chat_sessions;
CREATE POLICY "Users can view own sessions" ON public.ai_chat_sessions
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own sessions" ON public.ai_chat_sessions;
CREATE POLICY "Users can create own sessions" ON public.ai_chat_sessions
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own sessions" ON public.ai_chat_sessions;
CREATE POLICY "Users can delete own sessions" ON public.ai_chat_sessions
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_ai_chat_sessions_user ON public.ai_chat_sessions(user_id);

-- 12. AI CHAT MESSAGES
CREATE TABLE IF NOT EXISTS public.ai_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.ai_chat_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own messages" ON public.ai_chat_messages;
CREATE POLICY "Users can view own messages" ON public.ai_chat_messages
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.ai_chat_sessions s WHERE s.id = ai_chat_messages.session_id AND s.user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Users can create messages in own sessions" ON public.ai_chat_messages;
CREATE POLICY "Users can create messages in own sessions" ON public.ai_chat_messages
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.ai_chat_sessions s WHERE s.id = ai_chat_messages.session_id AND s.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_session ON public.ai_chat_messages(session_id);

-- 13. ATTENDANCE LOGS
CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ DEFAULT now(),
    check_in_method TEXT DEFAULT 'qr_scanner',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own attendance" ON public.attendance_logs;
CREATE POLICY "Users can view own attendance" ON public.attendance_logs
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Tenant admins can view attendance logs" ON public.attendance_logs;
CREATE POLICY "Tenant admins can view attendance logs" ON public.attendance_logs
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = attendance_logs.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Users can check in" ON public.attendance_logs;
CREATE POLICY "Users can check in" ON public.attendance_logs
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_attendance_logs_user ON public.attendance_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_attendance_logs_tenant ON public.attendance_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_attendance_logs_event ON public.attendance_logs(event_id);

-- 14. CALLS (WebRTC)
CREATE TABLE IF NOT EXISTS public.calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('video', 'audio')),
    status TEXT DEFAULT 'dialing' CHECK (status IN ('dialing', 'connected', 'rejected', 'ended', 'missed')),
    offer JSONB,
    answer JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    ended_at TIMESTAMPTZ
);

ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own calls" ON public.calls;
CREATE POLICY "Users can view own calls" ON public.calls
    FOR SELECT TO authenticated USING (auth.uid() = caller_id OR auth.uid() = recipient_id);

DROP POLICY IF EXISTS "Users can create calls" ON public.calls;
CREATE POLICY "Users can create calls" ON public.calls
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = caller_id);

DROP POLICY IF EXISTS "Users can update calls they're part of" ON public.calls;
CREATE POLICY "Users can update calls they're part of" ON public.calls
    FOR UPDATE TO authenticated USING (auth.uid() = caller_id OR auth.uid() = recipient_id);

CREATE INDEX IF NOT EXISTS idx_calls_caller ON public.calls(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_recipient ON public.calls(recipient_id);
CREATE INDEX IF NOT EXISTS idx_calls_status ON public.calls(status);

-- 15. CALL CANDIDATES (WebRTC ICE candidates)
CREATE TABLE IF NOT EXISTS public.call_candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    candidate JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.call_candidates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view candidates for their calls" ON public.call_candidates;
CREATE POLICY "Users can view candidates for their calls" ON public.call_candidates
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.calls c WHERE c.id = call_candidates.call_id AND (c.caller_id = auth.uid() OR c.recipient_id = auth.uid()))
    );

DROP POLICY IF EXISTS "Users can add candidates to their calls" ON public.call_candidates;
CREATE POLICY "Users can add candidates to their calls" ON public.call_candidates
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.calls c WHERE c.id = call_candidates.call_id AND (c.caller_id = auth.uid() OR c.recipient_id = auth.uid()))
    );

CREATE INDEX IF NOT EXISTS idx_call_candidates_call ON public.call_candidates(call_id);

-- 16. CHURCH BUSES
CREATE TABLE IF NOT EXISTS public.church_buses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    route TEXT,
    eta TEXT,
    next_stop TEXT,
    stops JSONB DEFAULT '[]',
    path JSONB DEFAULT '[]',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.church_buses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view church buses" ON public.church_buses;
CREATE POLICY "Anyone can view church buses" ON public.church_buses
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage buses" ON public.church_buses;
CREATE POLICY "Tenant admins can manage buses" ON public.church_buses
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = church_buses.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_church_buses_tenant ON public.church_buses(tenant_id);

-- 17. CHURCH CONNECTIONS
CREATE TABLE IF NOT EXISTS public.church_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    connected_church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'connected', 'blocked')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, connected_church_id)
);

ALTER TABLE public.church_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own connections" ON public.church_connections;
CREATE POLICY "Users can view own connections" ON public.church_connections
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create connections" ON public.church_connections;
CREATE POLICY "Users can create connections" ON public.church_connections
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_church_connections_user ON public.church_connections(user_id);

-- 18. CHURCH LIVE STATUS
CREATE TABLE IF NOT EXISTS public.church_live_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    is_live BOOLEAN DEFAULT false,
    stream_url TEXT,
    stream_key TEXT,
    title TEXT,
    viewer_count INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(church_id)
);

ALTER TABLE public.church_live_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view live status" ON public.church_live_status;
CREATE POLICY "Anyone can view live status" ON public.church_live_status
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Church admins can update live status" ON public.church_live_status;
CREATE POLICY "Church admins can update live status" ON public.church_live_status
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = church_live_status.church_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

-- 19. DISCIPLESHIP MILESTONES
CREATE TABLE IF NOT EXISTS public.discipleship_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    disciple_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mentor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.discipleship_milestones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own milestones" ON public.discipleship_milestones;
CREATE POLICY "Users can view own milestones" ON public.discipleship_milestones
    FOR SELECT TO authenticated USING (auth.uid() = disciple_id OR auth.uid() = mentor_id);

DROP POLICY IF EXISTS "Mentors can create milestones" ON public.discipleship_milestones;
CREATE POLICY "Mentors can create milestones" ON public.discipleship_milestones
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = mentor_id);

CREATE INDEX IF NOT EXISTS idx_discipleship_milestones_disciple ON public.discipleship_milestones(disciple_id);

-- 20. DISCIPLESHIP RELATIONSHIPS
CREATE TABLE IF NOT EXISTS public.discipleship_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mentor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mentee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed', 'cancelled')),
    started_at TIMESTAMPTZ DEFAULT now(),
    ended_at TIMESTAMPTZ,
    UNIQUE(mentor_id, mentee_id)
);

ALTER TABLE public.discipleship_relationships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own relationships" ON public.discipleship_relationships;
CREATE POLICY "Users can view own relationships" ON public.discipleship_relationships
    FOR SELECT TO authenticated USING (auth.uid() = mentor_id OR auth.uid() = mentee_id);

DROP POLICY IF EXISTS "Users can create relationships" ON public.discipleship_relationships;
CREATE POLICY "Users can create relationships" ON public.discipleship_relationships
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = mentor_id);

DROP POLICY IF EXISTS "Users can update own relationships" ON public.discipleship_relationships;
CREATE POLICY "Users can update own relationships" ON public.discipleship_relationships
    FOR UPDATE TO authenticated USING (auth.uid() = mentor_id OR auth.uid() = mentee_id);

CREATE INDEX IF NOT EXISTS idx_discipleship_relationships_mentor ON public.discipleship_relationships(mentor_id);
CREATE INDEX IF NOT EXISTS idx_discipleship_relationships_mentee ON public.discipleship_relationships(mentee_id);

-- 21. EVENT PARTICIPATING CHURCHES
CREATE TABLE IF NOT EXISTS public.event_participating_churches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    church_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
    UNIQUE(event_id, church_id)
);

ALTER TABLE public.event_participating_churches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view event participants" ON public.event_participating_churches;
CREATE POLICY "Anyone can view event participants" ON public.event_participating_churches
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Event hosts can manage participants" ON public.event_participating_churches;
CREATE POLICY "Event hosts can manage participants" ON public.event_participating_churches
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_participating_churches.event_id AND e.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_event_participating_churches_event ON public.event_participating_churches(event_id);

-- 22. EVENT REGISTRATIONS
CREATE TABLE IF NOT EXISTS public.event_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    check_in_status BOOLEAN DEFAULT false,
    registered_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(event_id, user_id)
);

ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own registrations" ON public.event_registrations;
CREATE POLICY "Users can view own registrations" ON public.event_registrations
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can register for events" ON public.event_registrations;
CREATE POLICY "Users can register for events" ON public.event_registrations
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Event hosts can manage registrations" ON public.event_registrations;
CREATE POLICY "Event hosts can manage registrations" ON public.event_registrations
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_registrations.event_id AND e.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_event_registrations_event ON public.event_registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_user ON public.event_registrations(user_id);

-- 23. EVENT RESOURCES
CREATE TABLE IF NOT EXISTS public.event_resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    resource_url TEXT NOT NULL,
    resource_type TEXT DEFAULT 'document',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.event_resources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view event resources" ON public.event_resources;
CREATE POLICY "Anyone can view event resources" ON public.event_resources
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Event hosts can manage resources" ON public.event_resources;
CREATE POLICY "Event hosts can manage resources" ON public.event_resources
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_resources.event_id AND e.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_event_resources_event ON public.event_resources(event_id);

-- 24. EXPANSION LEADS
CREATE TABLE IF NOT EXISTS public.expansion_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    church_name TEXT NOT NULL,
    location TEXT,
    interest_type TEXT DEFAULT 'notify_on_registration',
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'registered', 'closed')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.expansion_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own leads" ON public.expansion_leads;
CREATE POLICY "Users can view own leads" ON public.expansion_leads
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create leads" ON public.expansion_leads;
CREATE POLICY "Users can create leads" ON public.expansion_leads
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can manage all leads" ON public.expansion_leads;
CREATE POLICY "Superadmins can manage all leads" ON public.expansion_leads
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_expansion_leads_status ON public.expansion_leads(status);

-- 25. FEATURE REQUESTS
CREATE TABLE IF NOT EXISTS public.feature_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT DEFAULT 'Other',
    priority TEXT DEFAULT 'Medium',
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.feature_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own requests" ON public.feature_requests;
CREATE POLICY "Users can view own requests" ON public.feature_requests
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create requests" ON public.feature_requests;
CREATE POLICY "Users can create requests" ON public.feature_requests
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can manage all requests" ON public.feature_requests;
CREATE POLICY "Superadmins can manage all requests" ON public.feature_requests
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 26. FLYERS
CREATE TABLE IF NOT EXISTS public.flyers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.flyers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view flyers" ON public.flyers;
CREATE POLICY "Anyone can view flyers" ON public.flyers
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage flyers" ON public.flyers;
CREATE POLICY "Tenant admins can manage flyers" ON public.flyers
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = flyers.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_flyers_tenant ON public.flyers(tenant_id);

-- 27. JOB APPLICATIONS
CREATE TABLE IF NOT EXISTS public.job_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    applicant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    applicant_name TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own applications" ON public.job_applications;
CREATE POLICY "Users can view own applications" ON public.job_applications
    FOR SELECT TO authenticated USING (auth.uid() = applicant_id);

DROP POLICY IF EXISTS "Users can apply for jobs" ON public.job_applications;
CREATE POLICY "Users can apply for jobs" ON public.job_applications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = applicant_id);

DROP POLICY IF EXISTS "Job employers can view applications" ON public.job_applications;
CREATE POLICY "Job employers can view applications" ON public.job_applications
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.jobs j WHERE j.id = job_applications.job_id AND j.employer_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_job_applications_job ON public.job_applications(job_id);
CREATE INDEX IF NOT EXISTS idx_job_applications_applicant ON public.job_applications(applicant_id);

-- 28. KLIP COMMENTS
CREATE TABLE IF NOT EXISTS public.klip_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    klip_id UUID NOT NULL REFERENCES public.klips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.klip_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read comments" ON public.klip_comments;
CREATE POLICY "Anyone can read comments" ON public.klip_comments
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can comment" ON public.klip_comments;
CREATE POLICY "Authenticated users can comment" ON public.klip_comments
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own comments" ON public.klip_comments;
CREATE POLICY "Users can delete own comments" ON public.klip_comments
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_klip_comments_klip ON public.klip_comments(klip_id);

-- 29. LIVE CHAT MESSAGES
CREATE TABLE IF NOT EXISTS public.live_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT,
    user_photo TEXT,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.live_chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read live chat" ON public.live_chat_messages;
CREATE POLICY "Anyone can read live chat" ON public.live_chat_messages
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.live_chat_messages;
CREATE POLICY "Authenticated users can send messages" ON public.live_chat_messages
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate" ON public.live_chat_messages;
CREATE POLICY "Superadmins can moderate" ON public.live_chat_messages
    FOR DELETE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_live_chat_messages_tenant ON public.live_chat_messages(tenant_id);

-- 30. MEETING NOTES
CREATE TABLE IF NOT EXISTS public.meeting_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID,
    author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_private BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.meeting_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view meeting notes" ON public.meeting_notes;
CREATE POLICY "Users can view meeting notes" ON public.meeting_notes
    FOR SELECT TO authenticated USING (NOT is_private OR auth.uid() = author_id);

DROP POLICY IF EXISTS "Users can create notes" ON public.meeting_notes;
CREATE POLICY "Users can create notes" ON public.meeting_notes
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Users can manage own notes" ON public.meeting_notes;
CREATE POLICY "Users can manage own notes" ON public.meeting_notes
    FOR ALL TO authenticated USING (auth.uid() = author_id);

CREATE INDEX IF NOT EXISTS idx_meeting_notes_meeting ON public.meeting_notes(meeting_id);

-- 31. MEETING VOTES
CREATE TABLE IF NOT EXISTS public.meeting_votes (
    meeting_id UUID NOT NULL,
    voter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    option_selected TEXT NOT NULL,
    voted_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (meeting_id, voter_id)
);

ALTER TABLE public.meeting_votes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view vote results" ON public.meeting_votes;
CREATE POLICY "Anyone can view vote results" ON public.meeting_votes
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can vote once" ON public.meeting_votes;
CREATE POLICY "Users can vote once" ON public.meeting_votes
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = voter_id);

-- 32. MINISTRIES
CREATE TABLE IF NOT EXISTS public.ministries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    leader_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    meeting_day TEXT,
    meeting_time TEXT,
    meeting_location TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ministries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view ministries" ON public.ministries;
CREATE POLICY "Anyone can view ministries" ON public.ministries
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage ministries" ON public.ministries;
CREATE POLICY "Tenant admins can manage ministries" ON public.ministries
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = ministries.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_ministries_tenant ON public.ministries(tenant_id);

-- 33. MINISTRY MEMBERS
CREATE TABLE IF NOT EXISTS public.ministry_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ministry_id UUID NOT NULL REFERENCES public.ministries(id) ON DELETE CASCADE,
    profile_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member',
    joined_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(ministry_id, profile_id)
);

ALTER TABLE public.ministry_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view ministry members" ON public.ministry_members;
CREATE POLICY "Anyone can view ministry members" ON public.ministry_members
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can join ministries" ON public.ministry_members;
CREATE POLICY "Users can join ministries" ON public.ministry_members
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = profile_id);

DROP POLICY IF EXISTS "Ministry leaders can manage members" ON public.ministry_members;
CREATE POLICY "Ministry leaders can manage members" ON public.ministry_members
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.ministries m WHERE m.id = ministry_members.ministry_id AND m.leader_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_ministry_members_ministry ON public.ministry_members(ministry_id);

-- 34. NETWORK ACTIVITY
CREATE TABLE IF NOT EXISTS public.network_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    church_name TEXT,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    reference_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.network_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view network activity" ON public.network_activity;
CREATE POLICY "Anyone can view network activity" ON public.network_activity
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Churches can create activity" ON public.network_activity;
CREATE POLICY "Churches can create activity" ON public.network_activity
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = network_activity.church_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_network_activity_church ON public.network_activity(church_id);
CREATE INDEX IF NOT EXISTS idx_network_activity_type ON public.network_activity(type);
CREATE INDEX IF NOT EXISTS idx_network_activity_created ON public.network_activity(created_at DESC);

-- 35. ORGANIZATIONS
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    bishop_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    secretary_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    treasurer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view organizations" ON public.organizations;
CREATE POLICY "Anyone can view organizations" ON public.organizations
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Superadmins can manage organizations" ON public.organizations;
CREATE POLICY "Superadmins can manage organizations" ON public.organizations
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 36. PARKING ZONES
CREATE TABLE IF NOT EXISTS public.parking_zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    available INTEGER DEFAULT 0,
    total INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.parking_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view parking zones" ON public.parking_zones;
CREATE POLICY "Anyone can view parking zones" ON public.parking_zones
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage zones" ON public.parking_zones;
CREATE POLICY "Tenant admins can manage zones" ON public.parking_zones
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = parking_zones.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_parking_zones_tenant ON public.parking_zones(tenant_id);

-- 37. PASTORS CORNER
CREATE TABLE IF NOT EXISTS public.pastors_corner (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    pastor_name TEXT,
    pastor_photo TEXT,
    title TEXT NOT NULL,
    excerpt TEXT,
    content TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.pastors_corner ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read pastors corner" ON public.pastors_corner;
CREATE POLICY "Anyone can read pastors corner" ON public.pastors_corner
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Pastors can create posts" ON public.pastors_corner;
CREATE POLICY "Pastors can create posts" ON public.pastors_corner
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = pastors_corner.church_id AND p.role IN ('pastor', 'bishop', 'admin', 'superadmin'))
    );

DROP POLICY IF EXISTS "Pastors can manage own posts" ON public.pastors_corner;
CREATE POLICY "Pastors can manage own posts" ON public.pastors_corner
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = pastors_corner.church_id AND p.role IN ('pastor', 'bishop', 'admin', 'superadmin'))
    );

CREATE INDEX IF NOT EXISTS idx_pastors_corner_church ON public.pastors_corner(church_id);

-- 38. QUICK ROUTES
CREATE TABLE IF NOT EXISTS public.quick_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    time TEXT,
    via TEXT,
    icon TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.quick_routes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view quick routes" ON public.quick_routes;
CREATE POLICY "Anyone can view quick routes" ON public.quick_routes
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage routes" ON public.quick_routes;
CREATE POLICY "Tenant admins can manage routes" ON public.quick_routes
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = quick_routes.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_quick_routes_tenant ON public.quick_routes(tenant_id);

-- 39. READING PLANS
CREATE TABLE IF NOT EXISTS public.reading_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    total_days INTEGER NOT NULL,
    description TEXT,
    daily_verses JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.reading_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reading plans" ON public.reading_plans;
CREATE POLICY "Anyone can view reading plans" ON public.reading_plans
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins can manage plans" ON public.reading_plans;
CREATE POLICY "Admins can manage plans" ON public.reading_plans
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('admin', 'superadmin', 'employee'))
    );

-- 40. RIDE REGISTRATIONS
CREATE TABLE IF NOT EXISTS public.ride_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('driver', 'rider')),
    status TEXT DEFAULT 'offline' CHECK (status IN ('available', 'active', 'offline')),
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    vehicle_info TEXT,
    pre_registered_name TEXT,
    pre_registered_phone TEXT,
    pre_registered_role TEXT,
    updated_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ride_registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view ride registrations" ON public.ride_registrations;
CREATE POLICY "Anyone can view ride registrations" ON public.ride_registrations
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can register themselves" ON public.ride_registrations;
CREATE POLICY "Users can register themselves" ON public.ride_registrations
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own registration" ON public.ride_registrations;
CREATE POLICY "Users can update own registration" ON public.ride_registrations
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_ride_registrations_user ON public.ride_registrations(user_id);
CREATE INDEX IF NOT EXISTS idx_ride_registrations_type ON public.ride_registrations(type);
CREATE INDEX IF NOT EXISTS idx_ride_registrations_status ON public.ride_registrations(status);

-- 41. SERMON REACTIONS
CREATE TABLE IF NOT EXISTS public.sermon_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sermon_id UUID NOT NULL REFERENCES public.sermons(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reaction_type TEXT NOT NULL,
    content TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.sermon_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reactions" ON public.sermon_reactions;
CREATE POLICY "Anyone can view reactions" ON public.sermon_reactions
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can react" ON public.sermon_reactions;
CREATE POLICY "Users can react" ON public.sermon_reactions
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own reactions" ON public.sermon_reactions;
CREATE POLICY "Users can delete own reactions" ON public.sermon_reactions
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_sermon_reactions_sermon ON public.sermon_reactions(sermon_id);
CREATE INDEX IF NOT EXISTS idx_sermon_reactions_user ON public.sermon_reactions(user_id);

-- 42. TRAFFIC ALERTS
CREATE TABLE IF NOT EXISTS public.traffic_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    road TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'Moderate' CHECK (status IN ('Heavy', 'Moderate', 'Clear')),
    severity TEXT DEFAULT 'medium' CHECK (severity IN ('high', 'medium', 'low')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.traffic_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view traffic alerts" ON public.traffic_alerts;
CREATE POLICY "Anyone can view traffic alerts" ON public.traffic_alerts
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage alerts" ON public.traffic_alerts;
CREATE POLICY "Tenant admins can manage alerts" ON public.traffic_alerts
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = traffic_alerts.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_traffic_alerts_tenant ON public.traffic_alerts(tenant_id);

-- 43. USER FASTS
CREATE TABLE IF NOT EXISTS public.user_fasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    fast_type TEXT NOT NULL,
    duration_days INTEGER NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.user_fasts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own fasts" ON public.user_fasts;
CREATE POLICY "Users can view own fasts" ON public.user_fasts
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create fasts" ON public.user_fasts;
CREATE POLICY "Users can create fasts" ON public.user_fasts
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own fasts" ON public.user_fasts;
CREATE POLICY "Users can update own fasts" ON public.user_fasts
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_user_fasts_user ON public.user_fasts(user_id);

-- 44. USER NOTES
CREATE TABLE IF NOT EXISTS public.user_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT DEFAULT 'Untitled',
    topic TEXT,
    content TEXT,
    is_favorite BOOLEAN DEFAULT false,
    category TEXT DEFAULT 'general',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.user_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own notes" ON public.user_notes;
CREATE POLICY "Users can manage own notes" ON public.user_notes
    FOR ALL TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_user_notes_user ON public.user_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_notes_category ON public.user_notes(category);

-- 45. USER READING PROGRESS
CREATE TABLE IF NOT EXISTS public.user_reading_progress (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES public.reading_plans(id) ON DELETE CASCADE,
    completed_days INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, plan_id)
);

ALTER TABLE public.user_reading_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own progress" ON public.user_reading_progress;
CREATE POLICY "Users can view own progress" ON public.user_reading_progress
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own progress" ON public.user_reading_progress;
CREATE POLICY "Users can update own progress" ON public.user_reading_progress
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can upsert own progress" ON public.user_reading_progress;
CREATE POLICY "Users can upsert own progress" ON public.user_reading_progress
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- 46. YEAR PLANNER
CREATE TABLE IF NOT EXISTS public.year_planner (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    event_date DATE NOT NULL,
    is_central BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.year_planner ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view year planner" ON public.year_planner;
CREATE POLICY "Anyone can view year planner" ON public.year_planner
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Tenant admins can manage events" ON public.year_planner;
CREATE POLICY "Tenant admins can manage events" ON public.year_planner
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.tenant_id::uuid = year_planner.tenant_id AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_year_planner_tenant ON public.year_planner(tenant_id);
CREATE INDEX IF NOT EXISTS idx_year_planner_date ON public.year_planner(event_date);

-- ═══════════════════════════════════════════════════════════════════════════════
-- ENABLE REALTIME FOR NEW TABLES WHERE NEEDED
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    realtime_tables TEXT[] := ARRAY[
        'ai_chat_messages', 'calls', 'call_candidates', 'church_live_status',
        'event_registrations', 'klips', 'live_chat_messages', 'network_activity',
        'notifications', 'prayers', 'testimonies'
    ];
    t TEXT;
BEGIN
    FOREACH t IN ARRAY realtime_tables
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_rel pr
            JOIN pg_publication p ON p.oid = pr.prpubid
            JOIN pg_class c ON c.oid = pr.prrelid
            WHERE p.pubname = 'supabase_realtime' AND c.relname = t
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I;', t);
        END IF;
    END LOOP;
END $$;



