-- ════════════════════════════════════════════════════════════════
-- RLS ALWAYS_TRUE POLICY FIXES
-- Drops permissive USING (true) / WITH CHECK (true) policies
-- and recreates them with proper auth.uid() based conditions
-- ════════════════════════════════════════════════════════════════

-- 1. WALLET TRANSACTIONS: restrict INSERT to authenticated users
DROP POLICY IF EXISTS "System can insert wallet transactions" ON public.wallet_transactions;
CREATE POLICY "System can insert wallet transactions"
    ON public.wallet_transactions FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 2. NOTIFICATIONS: restrict INSERT to authenticated users
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
CREATE POLICY "System can insert notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 3. PLATFORM SETTINGS: restrict SELECT and ALL to admins only
DROP POLICY IF EXISTS "Anyone can view platform settings" ON public.platform_settings;
CREATE POLICY "Admins can view platform settings"
    ON public.platform_settings FOR SELECT
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

DROP POLICY IF EXISTS "Admins can update platform settings" ON public.platform_settings;
CREATE POLICY "Admins can manage platform settings"
    ON public.platform_settings FOR ALL
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    )
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

-- 4. TESTIMONIES: restrict UPDATE to owner or admin
DROP POLICY IF EXISTS "Authenticated users can update testimonies" ON public.testimonies;
CREATE POLICY "Users can update own testimonies"
    ON public.testimonies FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 5. SOCIAL POSTS: restrict UPDATE to owner or admin
DROP POLICY IF EXISTS "Authenticated users can update social posts" ON public.social_posts;
CREATE POLICY "Users can update own social posts"
    ON public.social_posts FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 6. DAILY BIBLE VERSES: restrict UPDATE/DELETE to admins
DROP POLICY IF EXISTS "Authenticated users can update daily bible verses" ON public.daily_bible_verses;
CREATE POLICY "Admins can manage daily bible verses"
    ON public.daily_bible_verses FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 7. PRAYERS: restrict UPDATE to owner or admin
DROP POLICY IF EXISTS "Authenticated users can update prayers" ON public.prayers;
CREATE POLICY "Users can update own prayers"
    ON public.prayers FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 8. RADIO STATIONS: restrict management to admins
DROP POLICY IF EXISTS "Admins can manage radio stations" ON public.radio_stations;
CREATE POLICY "Admins can manage radio stations"
    ON public.radio_stations FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 9. QUIZ SEASONS: restrict management to admins
DROP POLICY IF EXISTS "quiz_seasons_select" ON public.quiz_seasons;
CREATE POLICY "Admins can manage quiz seasons"
    ON public.quiz_seasons FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 10. QUIZ WEEKLY SCORES: restrict management to admins
DROP POLICY IF EXISTS "quiz_weekly_scores_select" ON public.quiz_weekly_scores;
CREATE POLICY "Admins can manage quiz weekly scores"
    ON public.quiz_weekly_scores FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 11. BIBLE STUDY SESSIONS: restrict management to admins
DROP POLICY IF EXISTS "bible_study_sessions_select" ON public.bible_study_sessions;
CREATE POLICY "Admins can manage bible study sessions"
    ON public.bible_study_sessions FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 12. NOTIFICATION CHANNELS: restrict to admins
DROP POLICY IF EXISTS "notification_channels_select" ON public.notification_channels;
CREATE POLICY "Admins can manage notification channels"
    ON public.notification_channels FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 13. GAME SCORES: restrict management to admins
DROP POLICY IF EXISTS "game_scores_select" ON public.game_scores;
CREATE POLICY "Admins can manage game scores"
    ON public.game_scores FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));

-- 14. QUIZ SEASON REWARDS: restrict to admins
DROP POLICY IF EXISTS "quiz_season_rewards_select" ON public.quiz_season_rewards;
CREATE POLICY "Admins can manage quiz season rewards"
    ON public.quiz_season_rewards FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));