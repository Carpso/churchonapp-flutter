-- ═══════════════════════════════════════════════════════════════════════════════
-- RLS AND SECURITY FIXES
-- Adds RLS to tables created without it, fixes overly permissive policies
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. NOTIFICATIONS — enable RLS + add missing columns
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
CREATE POLICY "System can insert notifications"
    ON public.notifications FOR INSERT
    WITH CHECK (true);

-- 2. CHURCHES — enable RLS
ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view churches" ON public.churches;
CREATE POLICY "Anyone can view churches"
    ON public.churches FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Church admins can update own church" ON public.churches;
CREATE POLICY "Church admins can update own church"
    ON public.churches FOR UPDATE
    USING (
        EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.tenant_id = churches.id
            AND p.role IN ('admin', 'pastor', 'bishop', 'superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Superadmins can manage churches" ON public.churches;
CREATE POLICY "Superadmins can manage churches"
    ON public.churches FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 3. RIDE REQUESTS — enable RLS
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own ride requests" ON public.ride_requests;
CREATE POLICY "Users can view own ride requests"
    ON public.ride_requests FOR SELECT
    USING (auth.uid() = rider_id OR auth.uid() = driver_id);

DROP POLICY IF EXISTS "Users can create ride requests" ON public.ride_requests;
CREATE POLICY "Users can create ride requests"
    ON public.ride_requests FOR INSERT
    WITH CHECK (auth.uid() = rider_id);

DROP POLICY IF EXISTS "Drivers can update assigned requests" ON public.ride_requests;
CREATE POLICY "Drivers can update assigned requests"
    ON public.ride_requests FOR UPDATE
    USING (auth.uid() = driver_id OR auth.uid() = rider_id);

-- 4. DELIVERY REQUESTS — enable RLS
ALTER TABLE public.delivery_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own delivery requests" ON public.delivery_requests;
CREATE POLICY "Users can view own delivery requests"
    ON public.delivery_requests FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = driver_id);

DROP POLICY IF EXISTS "Users can create delivery requests" ON public.delivery_requests;
CREATE POLICY "Users can create delivery requests"
    ON public.delivery_requests FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Drivers can update assigned deliveries" ON public.delivery_requests;
CREATE POLICY "Drivers can update assigned deliveries"
    ON public.delivery_requests FOR UPDATE
    USING (auth.uid() = driver_id OR auth.uid() = sender_id);

-- 5. PAYOUT REQUESTS — enable RLS
ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own payout requests" ON public.payout_requests;
CREATE POLICY "Users can view own payout requests"
    ON public.payout_requests FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create payout requests" ON public.payout_requests;
CREATE POLICY "Users can create payout requests"
    ON public.payout_requests FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can manage payouts" ON public.payout_requests;
CREATE POLICY "Superadmins can manage payouts"
    ON public.payout_requests FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 6. TITHE RECORDS — enable RLS
ALTER TABLE public.tithe_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own tithes" ON public.tithe_records;
CREATE POLICY "Users can view own tithes"
    ON public.tithe_records FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert tithes" ON public.tithe_records;
CREATE POLICY "System can insert tithes"
    ON public.tithe_records FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can view all tithes" ON public.tithe_records;
CREATE POLICY "Superadmins can view all tithes"
    ON public.tithe_records FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 7. SERMONS — enable RLS
ALTER TABLE public.sermons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view sermons" ON public.sermons;
CREATE POLICY "Anyone can view sermons"
    ON public.sermons FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Church admins can manage sermons" ON public.sermons;
CREATE POLICY "Church admins can manage sermons"
    ON public.sermons FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND (p.tenant_id = sermons.church_id OR p.role IN ('superadmin', 'employee')))
    );

-- 8. EVENTS — enable RLS
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view events" ON public.events;
CREATE POLICY "Anyone can view events"
    ON public.events FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can create events" ON public.events;
CREATE POLICY "Authenticated users can create events"
    ON public.events FOR INSERT
    WITH CHECK (auth.uid() = hosted_by OR auth.uid() = user_id);

DROP POLICY IF EXISTS "Event hosts can manage own events" ON public.events;
CREATE POLICY "Event hosts can manage own events"
    ON public.events FOR ALL
    USING (auth.uid() = hosted_by OR auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 9. TICKETS — enable RLS
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own tickets" ON public.tickets;
CREATE POLICY "Users can view own tickets"
    ON public.tickets FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can purchase tickets" ON public.tickets;
CREATE POLICY "Users can purchase tickets"
    ON public.tickets FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Event hosts can view tickets" ON public.tickets;
CREATE POLICY "Event hosts can view tickets"
    ON public.tickets FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.events e WHERE e.id = tickets.event_id AND (e.hosted_by = auth.uid() OR e.user_id = auth.uid()))
    );

-- 10. CHANNELS — enable RLS
ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view channels" ON public.channels;
CREATE POLICY "Anyone can view channels"
    ON public.channels FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can create channels" ON public.channels;
CREATE POLICY "Authenticated users can create channels"
    ON public.channels FOR INSERT
    WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Channel creators can manage channels" ON public.channels;
CREATE POLICY "Channel creators can manage channels"
    ON public.channels FOR ALL
    USING (auth.uid() = created_by
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 11. MESSAGES — enable RLS with proper policies
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
CREATE POLICY "Anyone can read messages"
    ON public.messages FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;
CREATE POLICY "Authenticated users can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own messages" ON public.messages;
CREATE POLICY "Users can delete own messages"
    ON public.messages FOR DELETE
    USING (auth.uid() = user_id);

-- 12. GROUPS — enable RLS
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view groups" ON public.groups;
CREATE POLICY "Anyone can view groups"
    ON public.groups FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Church admins can manage groups" ON public.groups;
CREATE POLICY "Church admins can manage groups"
    ON public.groups FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND (p.tenant_id = groups.church_id OR p.role IN ('superadmin', 'employee')))
    );

-- 13. GROUP MEMBERS — enable RLS
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view group members" ON public.group_members;
CREATE POLICY "Anyone can view group members"
    ON public.group_members FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can join groups" ON public.group_members;
CREATE POLICY "Users can join groups"
    ON public.group_members FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Group admins can manage members" ON public.group_members;
CREATE POLICY "Group admins can manage members"
    ON public.group_members FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 14. SMS LOGS — enable RLS
ALTER TABLE public.sms_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Superadmins can view sms logs" ON public.sms_logs;
CREATE POLICY "Superadmins can view sms logs"
    ON public.sms_logs FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "System can insert sms logs" ON public.sms_logs;
CREATE POLICY "Service can insert sms logs"
    ON public.sms_logs FOR INSERT
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 15. SOCIAL POSTS — enable RLS with proper moderation
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view social posts" ON public.social_posts;
CREATE POLICY "Anyone can view social posts"
    ON public.social_posts FOR SELECT
    USING (is_moderated = false OR is_moderated = true);

DROP POLICY IF EXISTS "Users can create own posts" ON public.social_posts;
CREATE POLICY "Users can create own posts"
    ON public.social_posts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own posts" ON public.social_posts;
CREATE POLICY "Users can update own posts"
    ON public.social_posts FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own posts" ON public.social_posts;
CREATE POLICY "Users can delete own posts"
    ON public.social_posts FOR DELETE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate all posts" ON public.social_posts;
CREATE POLICY "Superadmins can moderate all posts"
    ON public.social_posts FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 16. SOCIAL LIKES — enable RLS
ALTER TABLE public.social_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view likes" ON public.social_likes;
CREATE POLICY "Anyone can view likes"
    ON public.social_likes FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can like posts" ON public.social_likes;
CREATE POLICY "Users can like posts"
    ON public.social_likes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can unlike" ON public.social_likes;
CREATE POLICY "Users can unlike"
    ON public.social_likes FOR DELETE
    USING (auth.uid() = user_id);

-- 17. SOCIAL COMMENTS — enable RLS
ALTER TABLE public.social_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view comments" ON public.social_comments;
CREATE POLICY "Anyone can view comments"
    ON public.social_comments FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can comment" ON public.social_comments;
CREATE POLICY "Users can comment"
    ON public.social_comments FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own comments" ON public.social_comments;
CREATE POLICY "Users can delete own comments"
    ON public.social_comments FOR DELETE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can moderate comments" ON public.social_comments;
CREATE POLICY "Superadmins can moderate comments"
    ON public.social_comments FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 18. GROWTH HEATMAP DATA — enable RLS (public read, admin write)
ALTER TABLE public.growth_heatmap_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view heatmap data" ON public.growth_heatmap_data;
CREATE POLICY "Anyone can view heatmap data"
    ON public.growth_heatmap_data FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Superadmins can manage heatmap data" ON public.growth_heatmap_data;
CREATE POLICY "Superadmins can manage heatmap data"
    ON public.growth_heatmap_data FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 19. ROUTE OPTIMIZATIONS — enable RLS
ALTER TABLE public.route_optimizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Superadmins can manage route optimizations" ON public.route_optimizations;
CREATE POLICY "Superadmins can manage route optimizations"
    ON public.route_optimizations FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 20. RESOURCE ALLOCATIONS — enable RLS
ALTER TABLE public.resource_allocations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Superadmins can manage resource allocations" ON public.resource_allocations;
CREATE POLICY "Superadmins can manage resource allocations"
    ON public.resource_allocations FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 21. LENCO PAYOUTS — enable RLS
ALTER TABLE public.lenco_payouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own payouts" ON public.lenco_payouts;
CREATE POLICY "Users can view own payouts"
    ON public.lenco_payouts FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins can manage payouts" ON public.lenco_payouts;
CREATE POLICY "Superadmins can manage payouts"
    ON public.lenco_payouts FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee'))
    );

-- 22. WALLET TRANSACTIONS — add UPDATE/DELETE policies
DROP POLICY IF EXISTS "Users can view own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own wallet transactions"
    ON public.wallet_transactions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert wallet transactions" ON public.wallet_transactions;
CREATE POLICY "System can insert wallet transactions"
    ON public.wallet_transactions FOR INSERT
    WITH CHECK (true);

-- 23. TRANSACTIONS — add admin read policy
DROP POLICY IF EXISTS "Leaders can view church transactions" ON public.transactions;
CREATE POLICY "Leaders can view church transactions"
    ON public.transactions FOR SELECT
    USING (
        tenant_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.tenant_id = transactions.tenant_id
            AND p.role IN ('admin', 'pastor', 'bishop', 'general_treasurer', 'general_secretary', 'superadmin', 'employee')
        )
    );

-- 24. Ensure profiles has tenant_id for church association
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL;

-- 25. Add missing columns to notifications (if not already added by 20260704)
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS reference_id TEXT;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id);

-- 26. Add missing columns to profiles (if not already present from auth trigger or old migrations)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS streak_count INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS kyc_status TEXT DEFAULT 'unverified';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS referral_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 27. Add missing columns to other existing tables
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS reference_id TEXT;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id);

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS hosted_by UUID REFERENCES auth.users(id);
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS host_type TEXT DEFAULT 'church';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS is_paid_event BOOLEAN DEFAULT false;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_price DOUBLE PRECISION;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ticket_limit INTEGER;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS tickets_sold INTEGER DEFAULT 0;

ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS transcript TEXT;
ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS ai_summary TEXT;

ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial';

-- 28. Enable realtime for core tables
DO $$
DECLARE
    realtime_tables TEXT[] := ARRAY[
        'events', 'sermons', 'social_posts', 'social_likes', 'social_comments',
        'ride_requests', 'delivery_requests', 'channels', 'groups', 'group_members',
        'wallet_transactions', 'payout_requests', 'tithe_records',
        'growth_heatmap_data', 'route_optimizations', 'resource_allocations',
        'lenco_payouts', 'church_live_status'
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
