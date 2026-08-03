-- P2-25: Fix notifications INSERT — restrict to self or system
DO $$ BEGIN
  DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- Users can only insert notifications for themselves
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Users can insert own notifications"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- P2-26: Remove anon access from sensitive tables
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view churches" ON public.churches;
  DROP POLICY IF EXISTS "Authenticated users can view churches" ON public.churches;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Authenticated users can view churches"
  ON public.churches FOR SELECT
  TO authenticated
  USING (true);

DO $$ BEGIN
  DROP POLICY IF EXISTS "Admins can view platform settings" ON public.platform_settings;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Admins can view platform settings"
  ON public.platform_settings FOR SELECT
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );

DO $$ BEGIN
  DROP POLICY IF EXISTS "Prayers select policy" ON public.prayers;
  DROP POLICY IF EXISTS "Authenticated users can view prayers" ON public.prayers;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Authenticated users can view prayers"
  ON public.prayers FOR SELECT
  TO authenticated
  USING (true);

DO $$ BEGIN
  DROP POLICY IF EXISTS "Testimonies select policy" ON public.testimonies;
  DROP POLICY IF EXISTS "Authenticated users can view testimonies" ON public.testimonies;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Authenticated users can view testimonies"
  ON public.testimonies FOR SELECT
  TO authenticated
  USING (true);

DO $$ BEGIN
  DROP POLICY IF EXISTS "Quiz events select policy" ON public.quiz_events;
  DROP POLICY IF EXISTS "Authenticated users can view quiz events" ON public.quiz_events;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Authenticated users can view quiz events"
  ON public.quiz_events FOR SELECT
  TO authenticated
  USING (true);
